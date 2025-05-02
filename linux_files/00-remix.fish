#!/usr/bin/env fish

# Only the default WSL user should run this script
if not (id -Gn | grep -c "adm.*wheel\|wheel.*adm" > /dev/null)
    return
end

set systemd_saved_environment "$HOME/.systemd.env"

function save_environment
    echo "PATH='$PATH'" > $systemd_saved_environment
    echo "WSL_DISTRO_NAME='$WSL_DISTRO_NAME'" >> $systemd_saved_environment
    echo "WSL_INTEROP='$WSL_INTEROP'" >> $systemd_saved_environment
    echo "WSL_SYSTEMD_EXECUTION_ARGS='$WSL_SYSTEMD_EXECUTION_ARGS'" >> $systemd_saved_environment
    echo "PULSE_SERVER='$PULSE_SERVER'" >> $systemd_saved_environment
    echo "WSL2_GUI_APPS_ENABLED='$WSL2_GUI_APPS_ENABLED'" >> $systemd_saved_environment
end

function setup_interop
    # shellcheck disable=SC2155,SC2012
    set WSL_INTEROP (ls -U /run/WSL/*_interop | tail -1)
end

function setup_display
    if test -n "$XRDP_SESSION"
        if test -f $systemd_saved_environment
            source $systemd_saved_environment
        end

        if test -n "$WSL_INTEROP"
            set -x WSL2 1
            setup_interop
        end

        if test -n "$WSL2_GUI_APPS_ENABLED"
            set -e WAYLAND_DISPLAY
            rm -f /run/user/(id -u)/wayland*
        end
        
        return
    end

    if test -n "$SSH_CONNECTION"
        return
    end

    # Check whether it is WSL1 or WSL2
    if test -n "$WSL_INTEROP"
        set -x WSL2 1

        if test -n "$DISPLAY"
            if test -n "$WSL2_GUI_APPS_ENABLED"
                set uid (id -u)
                ln -fs /mnt/wslg/runtime-dir/wayland-0 /run/user/$uid/
                ln -fs /mnt/wslg/runtime-dir/wayland-0.lock /run/user/$uid/
                ln -fs /mnt/wslg/runtime-dir/pulse /run/user/$uid/pulse
            end
            return
        end

        # Enable external x display for WSL 2
        set ipconfig_exec (wslpath "C:\\Windows\\System32\\ipconfig.exe")
        if not command -v ipconfig.exe > /dev/null 2>&1
            set ipconfig_exec (command -v ipconfig.exe)
        end

        set wsl2_d_tmp (eval "$ipconfig_exec 2> /dev/null" | grep -n -m 1 "Default Gateway.*: [0-9a-z]" | cut -d : -f 1)

        if test -n "$wsl2_d_tmp"
            set wsl2_d_tmp (eval "$ipconfig_exec" | sed "$((wsl2_d_tmp - 4))"','"$((wsl2_d_tmp + 0))"'!d' | grep IPv4 | cut -d : -f 2 | sed -e "s|\s||g" -e "s|\r||g")
            set -x DISPLAY "$wsl2_d_tmp:0"
        else
            set wsl2_d_tmp (grep </etc/resolv.conf nameserver | awk '{print $2}')
            set -x DISPLAY "$wsl2_d_tmp:0"
        end

        set -e wsl2_d_tmp
        set -e ipconfig_exec
    else
        # Enable external x display for WSL 1
        set -x DISPLAY "localhost:0"
        set -e WSL2
    end
end

function setup_dbus
    # If dbus-launch is installed, then load it
    if not command -v dbus-launch > /dev/null
        return
    end

    # Enabled via systemd
    if test -n "$DBUS_SESSION_BUS_ADDRESS"
        return
    end

    set dbus_pid (pidof dbus-daemon | cut -d' ' -f1)

    if test -z "$dbus_pid"
        set dbus_env (timeout 2s dbus-launch --auto-syntax)
        eval $dbus_env
        echo $dbus_env > "/tmp/dbus_env_$DBUS_SESSION_BUS_PID"
        set -e dbus_env
    else
        eval (cat "/tmp/dbus_env_$dbus_pid")
    end

    set -e dbus_pid
end

setup_display
setup_dbus

# Speed up some GUI apps like gedit
set -x NO_AT_BRIDGE 1

# Fix 'clear' scrolling issues
alias clear="clear -x"

# Custom aliases
alias ll="ls -al"
alias winget="powershell.exe winget"
alias wsl="wsl.exe"

if test -n "$WSL2"
    # Setup video acceleration
    set -x VDPAU_DRIVER "d3d12"
    set -x LIBVA_DRIVER_NAME "d3d12"
    set -x GALLIUM_DRIVER "d3d12"
end

# Fix $PATH for Systemd
set SYSTEMD_PID (ps -C systemd -o pid= | head -n1)

if test -z "$SYSTEMD_PID"
    save_environment
else if test -n "$SYSTEMD_PID" -a "$SYSTEMD_PID" -eq 1 -a -f "$HOME/.systemd.env"
    source $systemd_saved_environment
    setup_interop
end

# Check if we have Windows Path
if test -z "$WIN_HOME" -a (command -v cmd.exe > /dev/null 2>&1)
    # Create a symbolic link to the Windows home
    set wHomeWinPath (cmd.exe /c 'cd %SYSTEMDRIVE%\ && echo %HOMEDRIVE%%HOMEPATH%' 2>/dev/null | tr -d '\r')

    if test (string length $wHomeWinPath) -le 3
        set wHomeWinPath (cmd.exe /c 'cd %SYSTEMDRIVE%\ && echo %USERPROFILE%' 2>/dev/null | tr -d '\r')
    end

    set -x WIN_HOME (wslpath -u "$wHomeWinPath")

    set win_home_lnk "$HOME/winhome"
    if not test -e $win_home_lnk
        ln -s -f $WIN_HOME $win_home_lnk > /dev/null 2>&1
    end

    set -e win_home_lnk
end
