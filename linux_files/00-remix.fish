#!/usr/bin/env fish
#
# /etc/fish/conf.d/00-wsl-display.fish
# Runs for every interactive shell.  “return” is used instead of “exit”
# so that the rest of the shell start-up continues.

### 0.   Helpers #############################################################

set -g systemd_saved_environment "$HOME/.systemd.env"
set -g SYSTEMD_PID (ps -C systemd -o pid= | head -n1)

function load_env_file --description 'Import bash-style  VAR='\''VALUE'\''  lines'
    set -l file $argv[1]
    if not test -f $file
        return
    end

    while read -l line
        # Skip blank lines or comments
        if not string length --quiet $line; or string match -q '#*' -- $line
            continue
        end

        # Accept KEY='VALUE'  (no spaces around =)
        if not string match -qre '^[A-Za-z_][A-Za-z0-9_]*=' -- $line
            continue
        end

        # Split only on the first '='
        set -l pair (string split -m 1 '=' -- $line)
        set -l key  $pair[1]
        set -l val  $pair[2]

        # Remove leading and trailing single quotes, if present
        set val (string trim --chars "'" -- $val)

        # Export into the current environment
        set -gx $key $val
    end < $file
end

function save_environment
    printf "PATH='%s'\n"          $PATH            >  $systemd_saved_environment
    printf "WSL_DISTRO_NAME='%s'\n"   $WSL_DISTRO_NAME   >> $systemd_saved_environment
    printf "WSL_INTEROP='%s'\n"       $WSL_INTEROP       >> $systemd_saved_environment
    printf "WSL_SYSTEMD_EXECUTION_ARGS='%s'\n" $WSL_SYSTEMD_EXECUTION_ARGS >> $systemd_saved_environment
    printf "PULSE_SERVER='%s'\n"      $PULSE_SERVER      >> $systemd_saved_environment
    printf "WAYLAND_DISPLAY='%s'\n"   $WAYLAND_DISPLAY   >> $systemd_saved_environment
end

function setup_interop
    set -gx WSL_INTEROP (ls -U /run/WSL/*_interop 2>/dev/null | tail -n1)
end

### 1. Privilege check #######################################################

if id -Gn | grep -qE 'adm.*wheel|wheel.*adm'
    # OK – continue
else
    return
end

### 2. Display / audio #######################################################

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

    # Remote SSH?  Nothing to do.
    if test -n "$SSH_CONNECTION"
        return
    end

    # ---------- WSL 2 -------------------------------------------------------
    if test -n "$WSL_INTEROP"
        set -gx WSL2 1

        if test -n "$DISPLAY"
            if test -n "$SYSTEMD_PID"
                set -l uid (id -u)
                ln -fs /mnt/wslg/runtime-dir/wayland-0       /run/user/$uid/
                ln -fs /mnt/wslg/runtime-dir/wayland-0.lock  /run/user/$uid/
                ln -fs /mnt/wslg/runtime-dir/pulse           /run/user/$uid/pulse
            end
            return
        end

        # --- Figure out Windows host IP for X11 ---------------------------
        set -l ipconfig_exec (wslpath "C:\\Windows\\System32\\ipconfig.exe")
        if command -v ipconfig.exe >/dev/null 2>&1
            set ipconfig_exec (command -v ipconfig.exe)
        end

        # first, find the line number of the gateway entry
        set -l gw_line (eval $ipconfig_exec 2>/dev/null \
                         | grep -n -m1 'Default Gateway.*: [0-9a-fA-F]' \
                         | cut -d: -f1)

        if test -n "$gw_line"
            # compute start/end positions
            set -l start (math $gw_line - 4)
            set -l end   $gw_line

            # now call sed using those vars
            set -l wsl2_ip (eval $ipconfig_exec \
                             | sed "${start},${end}!d" \
                             | grep IPv4 \
                             | cut -d: -f2 \
                             | tr -d ' \r')
        else
            set -l wsl2_ip (grep -m1 nameserver /etc/resolv.conf | awk '{print $2}')
        end

        # finally export DISPLAY
        set -gx DISPLAY "$wsl2_ip:0"
        return
    end

    # ---------- WSL 1 -------------------------------------------------------
    set -gx DISPLAY "localhost:0"
    set -e  WSL2
end

### 3. DBus ###############################################################

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

# -------------------------------------------------------------------------

setup_display
setup_dbus

# Speed-ups and handy aliases
set -gx NO_AT_BRIDGE 1
alias  clear  "clear -x"
alias  ll     "ls -al"
alias  winget "powershell.exe winget"
alias  wsl    "wsl.exe"

# GPU / VAAPI tweaks for WSL 2
if test -n "$WSL2"
    set -gx VDPAU_DRIVER        d3d12
    set -gx LIBVA_DRIVER_NAME   d3d12
    set -gx GALLIUM_DRIVER      d3d12
end

### 4. Persist env for systemd ##############################################

if test -z "$SYSTEMD_PID"
    save_environment
else if test "$SYSTEMD_PID" -eq 1; and test -f $systemd_saved_environment; and test -n "$WSL_SYSTEMD_EXECUTION_ARGS"
    load_env_file $systemd_saved_environment
    setup_interop
end

### 5. Windows home link ####################################################

if test -z "$WIN_HOME"; and command -v cmd.exe >/dev/null 2>&1
    set -l wHomeWinPath (cmd.exe /c 'cd %SYSTEMDRIVE%\ && echo %HOMEDRIVE%%HOMEPATH%' | tr -d '\r')
    if test (string length $wHomeWinPath) -le 3
        set wHomeWinPath (cmd.exe /c 'cd %SYSTEMDRIVE%\ && echo %USERPROFILE%' | tr -d '\r')
    end
    set -gx WIN_HOME (wslpath -u $wHomeWinPath)

    set -l win_home_lnk "$HOME/winhome"
    if not test -e $win_home_lnk
        ln -sf $WIN_HOME $win_home_lnk >/dev/null 2>&1
    end
end
