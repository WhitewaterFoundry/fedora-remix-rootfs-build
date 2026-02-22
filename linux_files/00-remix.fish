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
    begin
        if test -n "$PATH"
            echo "PATH='$PATH'"
        end
        if test -n "$WSL_DISTRO_NAME"
            echo "WSL_DISTRO_NAME='$WSL_DISTRO_NAME'"
        end
        if test -n "$WSL_INTEROP"
            echo "WSL_INTEROP='$WSL_INTEROP'"
        end
        if test -n "$WSL_SYSTEMD_EXECUTION_ARGS"
            echo "WSL_SYSTEMD_EXECUTION_ARGS='$WSL_SYSTEMD_EXECUTION_ARGS'"
        end
        if test -n "$PULSE_SERVER"
            echo "PULSE_SERVER='$PULSE_SERVER'"
        end
        if test -n "$WAYLAND_DISPLAY"
            echo "WAYLAND_DISPLAY='$WAYLAND_DISPLAY'"
        end
    end > $systemd_saved_environment
end

function setup_interop
    set -gx WSL_INTEROP (ls -U /run/WSL/*_interop 2>/dev/null | tail -n1)
end

function define_xdg_environment
    # XDG Base Directory Specification
    # https://specifications.freedesktop.org/basedir/latest/

    if test -z "$XDG_DATA_HOME"
        set -gx XDG_DATA_HOME "$HOME/.local/share"
    end
    mkdir -p "$XDG_DATA_HOME" 2>/dev/null; or true

    if test -z "$XDG_CONFIG_HOME"
        set -gx XDG_CONFIG_HOME "$HOME/.config"
    end
    mkdir -p "$XDG_CONFIG_HOME" 2>/dev/null; or true

    if test -z "$XDG_STATE_HOME"
        set -gx XDG_STATE_HOME "$HOME/.local/state"
    end
    mkdir -p "$XDG_STATE_HOME" 2>/dev/null; or true

    if test -z "$XDG_CACHE_HOME"
        set -gx XDG_CACHE_HOME "$HOME/.cache"
    end
    mkdir -p "$XDG_CACHE_HOME" 2>/dev/null; or true

    if test -z "$XDG_DATA_DIRS"
        set -gx XDG_DATA_DIRS "/usr/local/share:/usr/share"
    end

    if test -z "$XDG_CONFIG_DIRS"
        set -gx XDG_CONFIG_DIRS "/etc/xdg"
    end
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
        if test -f "$systemd_saved_environment"
            load_env_file $systemd_saved_environment
        end

        if test -n "$WSL_INTEROP"
            set -gx WSL2 1
            setup_interop
        end

        set -e WAYLAND_DISPLAY
        if test -n "$SYSTEMD_PID"
            rm -f /run/user/(id -u)/wayland* 2>/dev/null
        end

        if test -z "$PULSE_SERVER"
            pulseaudio --enable-memfd=FALSE --disable-shm=TRUE --log-target=syslog --start >/dev/null 2>&1
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
            set -l uid (id -u)

            set -l user_path "/run/user/$uid"
            if not test -d "$user_path"
                sudo /usr/local/bin/create_userpath "$uid" 2>/dev/null
            end

            if test -z "$SYSTEMD_PID"
                set -gx XDG_RUNTIME_DIR "$user_path"
            end

            set -l wslg_runtime_dir "/mnt/wslg/runtime-dir"

            ln -fs "$wslg_runtime_dir"/wayland-0 "$user_path"/ 2>/dev/null
            ln -fs "$wslg_runtime_dir"/wayland-0.lock "$user_path"/ 2>/dev/null

            set -l pulse_path "$user_path/pulse"
            set -l wslg_pulse_dir "$wslg_runtime_dir"/pulse

            if not test -d "$pulse_path"
                mkdir -p "$pulse_path" 2>/dev/null

                ln -fs "$wslg_pulse_dir"/native "$pulse_path"/ 2>/dev/null
                ln -fs "$wslg_pulse_dir"/pid "$pulse_path"/ 2>/dev/null

            else if test -S "$pulse_path/native"
                # Handle stale socket: remove it and recreate as symlink to WSLg pulse
                rm -f "$pulse_path/native" 2>/dev/null
                ln -fs "$wslg_pulse_dir"/native "$pulse_path"/ 2>/dev/null
            end

            return
        end

        # enable external x display for WSL 2
        set -l route_exec (wslpath 'C:\Windows\system32\route.exe')

        if set -l route_exec_path (command -v route.exe 2>/dev/null)
            set route_exec "$route_exec_path"
        end

        set -l wsl2_d_tmp (eval "$route_exec print 2>/dev/null" | grep -a 0.0.0.0 | head -1 | awk '{print $4}')

        if test -n "$wsl2_d_tmp"
            set -gx DISPLAY "$wsl2_d_tmp":0
        else
            set wsl2_d_tmp (ip route | grep default | awk '{print $3; exit;}')
            set -gx DISPLAY "$wsl2_d_tmp":0
        end
    else
        # WSL1 fallback
        set -gx DISPLAY "localhost:0"
        set -e WSL2
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

    # Use a per-user directory for storing the D-Bus environment
    set -l dbus_env_dir (if test -n "$XDG_RUNTIME_DIR"; echo "$XDG_RUNTIME_DIR"; else; echo "$HOME/.cache"; end)
    mkdir -p "$dbus_env_dir" 2>/dev/null; or true

    set -l dbus_pid (pidof -s dbus-daemon)

    if test -z "$dbus_pid"
        set -l dbus_env (timeout 2s dbus-launch --auto-syntax); or return

        # Extract and export only the expected variables from dbus-launch output
        set -l addr (printf '%s\n' $dbus_env | sed -n 's/^DBUS_SESSION_BUS_ADDRESS='\''\(.*\)'\'';$/\1/p')
        set -l pid_val (printf '%s\n' $dbus_env | sed -n 's/^DBUS_SESSION_BUS_PID=\([0-9][0-9]*\);$/\1/p')

        if test -n "$addr"; and test -n "$pid_val"
            set -gx DBUS_SESSION_BUS_ADDRESS "$addr"
            set -gx DBUS_SESSION_BUS_PID "$pid_val"

            set -l dbus_env_file "$dbus_env_dir/dbus_env_$DBUS_SESSION_BUS_PID"
            printf "DBUS_SESSION_BUS_ADDRESS='%s'\n" "$DBUS_SESSION_BUS_ADDRESS" > "$dbus_env_file"
            printf "DBUS_SESSION_BUS_PID='%s'\n" "$DBUS_SESSION_BUS_PID" >> "$dbus_env_file"
            chmod 600 "$dbus_env_file" 2>/dev/null; or true
        end
    else
        # Reuse existing dbus session
        set -l dbus_env_file "$dbus_env_dir/dbus_env_$dbus_pid"
        if test -f "$dbus_env_file"
            set -l addr (sed -n 's/^DBUS_SESSION_BUS_ADDRESS='\''\(.*\)'\''$/\1/p' "$dbus_env_file")
            set -l pid_val (sed -n 's/^DBUS_SESSION_BUS_PID='\''\([0-9][0-9]*\)'\''$/\1/p' "$dbus_env_file")
            if test -n "$addr"; and test -n "$pid_val"
                set -gx DBUS_SESSION_BUS_ADDRESS "$addr"
                set -gx DBUS_SESSION_BUS_PID "$pid_val"
            end
        end
    end
end

# invoke
define_xdg_environment
setup_display

if test -z "$SYSTEMD_PID"; and test -z "$DBUS_SESSION_BUS_ADDRESS"
    setup_dbus
end

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

    sudo /usr/local/bin/fedoraremix-load-vgem-module
end

### ————————————————————————————————
### 5. Persist for systemd

if test -z "$SYSTEMD_PID"
    save_environment
else if test "$SYSTEMD_PID" -eq 1; and test -f $systemd_saved_environment; and test -n "$WSL_SYSTEMD_EXECUTION_ARGS"
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
