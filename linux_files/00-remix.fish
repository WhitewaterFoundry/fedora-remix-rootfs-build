#!/usr/bin/env fish
#
# /etc/fish/conf.d/00-remix.fish
# Configures WSL display, DBus, environment persistence, aliases, etc.

### ————————————————————————————————
### Globals
set -g systemd_saved_environment "$HOME/.systemd.env"
set -g SYSTEMD_PID (ps -C systemd -o pid= | head -n1)

### ————————————————————————————————
### Helpers

function load_env_file --description 'Import lines like VAR='\''VALUE'\'''
    set -l file $argv[1]
    if not test -f $file
        return
    end

    while read -l line
        # skip empty lines or comments
        if test -z "$line"; or string match -q '#*' -- $line
            continue
        end

        # must start KEY=
        if not string match -qre '^[A-Za-z_][A-Za-z0-9_]*=' -- $line
            continue
        end

        # split only on first '='
        set -l pair (string split -m1 '=' -- $line)
        set -l key  $pair[1]
        set -l val  $pair[2]

        # strip surrounding single-quotes if present
        set val (string trim --chars "'" -- $val)

        # export
        set -gx $key $val
    end < $file
end

function save_environment
    printf "PATH='%s'\n"                    $PATH                            >  $systemd_saved_environment
    printf "WSL_DISTRO_NAME='%s'\n"         $WSL_DISTRO_NAME                 >> $systemd_saved_environment
    printf "WSL_INTEROP='%s'\n"             $WSL_INTEROP                     >> $systemd_saved_environment
    printf "WSL_SYSTEMD_EXECUTION_ARGS='%s'\n" $WSL_SYSTEMD_EXECUTION_ARGS   >> $systemd_saved_environment
    printf "PULSE_SERVER='%s'\n"            $PULSE_SERVER                    >> $systemd_saved_environment
    printf "WAYLAND_DISPLAY='%s'\n"         $WAYLAND_DISPLAY                 >> $systemd_saved_environment
end

function setup_interop
    set -gx WSL_INTEROP (ls -U /run/WSL/*_interop 2>/dev/null | tail -n1)
end

### ————————————————————————————————
### 1. Privilege check
if id -Gn | grep -qE 'adm.*wheel|wheel.*adm'
    # ok
else
    return
end

### ————————————————————————————————
### 2. Display + WSL IPC

function setup_display
    # XRDP session
    if test -n "$XRDP_SESSION"
        load_env_file $systemd_saved_environment

        if test -n "$WSL_INTEROP"
            set -gx WSL2 1
            setup_interop
        end

        set -e WAYLAND_DISPLAY
        if test -n "$SYSTEMD_PID"
            rm -f /run/user/(id -u)/wayland*
        end
        return
    end

    # SSH session: nothing to do
    if test -n "$SSH_CONNECTION"
        return
    end

    # WSL2?
    if test -n "$WSL_INTEROP"
        set -gx WSL2 1

        # inside WSLg (DISPLAY set)?
        if test -n "$DISPLAY"
            if test -n "$SYSTEMD_PID"
                set -l uid (id -u)
                ln -fs /mnt/wslg/runtime-dir/wayland-0       /run/user/$uid/
                ln -fs /mnt/wslg/runtime-dir/wayland-0.lock  /run/user/$uid/
                ln -fs /mnt/wslg/runtime-dir/pulse           /run/user/$uid/pulse
            end
            return
        end

        # compute Windows host IP for X11
        set -l ipconfig_exec (wslpath "C:\\Windows\\System32\\ipconfig.exe")
        if command -v ipconfig.exe > /dev/null 2>&1
            set ipconfig_exec (command -v ipconfig.exe)
        end

        set -l gw_line ( $ipconfig_exec 2>/dev/null | grep -n -m1 'Default Gateway.*: [0-9a-fA-F]' | cut -d: -f1 )
        if test -n "$gw_line"
            set -l start (math $gw_line - 4)
            set -l end   $gw_line
            set -l wsl2_ip ( $ipconfig_exec | sed "$start,$end!d" | grep IPv4 | cut -d: -f2 | tr -d ' \r' )
        else
            set -l wsl2_ip (grep -m1 nameserver /etc/resolv.conf | awk '{print $2}')
        end
        set -gx DISPLAY "$wsl2_ip:0"
    else
        # WSL1 fallback
        set -gx DISPLAY "localhost:0"
        set -e  WSL2
    end
end

### ————————————————————————————————
### 3. DBus session

function setup_dbus
    if not command -v dbus-launch >/dev/null
        return
    end
    if test -n "$DBUS_SESSION_BUS_ADDRESS"
        return
    end

    set -l dbus_pid (pidof dbus-daemon | head -n1)
    if test -z "$dbus_pid"
        set -l dbus_env (timeout 2s dbus-launch --auto-syntax)
        eval $dbus_env
        echo $dbus_env > /tmp/dbus_env_$DBUS_SESSION_BUS_PID
    else
        eval (cat /tmp/dbus_env_$dbus_pid)
    end
end

# invoke
setup_display
setup_dbus

### ————————————————————————————————
### 4. Aliases & tweaks

set -gx NO_AT_BRIDGE 1

alias clear  "clear -x"
alias ll     "ls -al"
alias winget "powershell.exe winget"
alias wsl    "wsl.exe"

if test -n "$WSL2"
    set -gx VDPAU_DRIVER      d3d12
    set -gx LIBVA_DRIVER_NAME d3d12
    set -gx GALLIUM_DRIVER    d3d12
end

### ————————————————————————————————
### 5. Persist for systemd

if test -z "$SYSTEMD_PID"
    save_environment
else if test $SYSTEMD_PID -eq 1; and test -f $systemd_saved_environment; and test -n "$WSL_SYSTEMD_EXECUTION_ARGS"
    load_env_file $systemd_saved_environment
    setup_interop
end

### ————————————————————————————————
### 6. Windows‐home symlink

if test -z "$WIN_HOME"; and command -v cmd.exe > /dev/null 2>&1
    set -l wHomeWinPath (cmd.exe /c 'cd %SYSTEMDRIVE%\ && echo %HOMEDRIVE%%HOMEPATH%' 2>/dev/null | tr -d '\r')
    if test (string length $wHomeWinPath) -le 3
        set wHomeWinPath (cmd.exe /c 'cd %SYSTEMDRIVE%\ && echo %USERPROFILE%' 2>/dev/null | tr -d '\r')
    end

    set -gx WIN_HOME (wslpath -u $wHomeWinPath)
    set -l win_home_lnk "$HOME/winhome"
    if not test -e $win_home_lnk
        ln -sf $WIN_HOME $win_home_lnk > /dev/null 2>&1
    end
end
