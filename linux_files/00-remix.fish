#!/usr/bin/env fish

# Only the default WSL user should run this script
if not (id -Gn | grep -c "adm.*wheel\|wheel.*adm" > /dev/null)
    return
end

set systemd_saved_environment "$HOME/.systemd.env"

set SYSTEMD_PID (ps -C systemd -o pid= | head -n1)

function save_environment
    echo "PATH='$PATH'" > $systemd_saved_environment
    echo "WSL_DISTRO_NAME='$WSL_DISTRO_NAME'" >> $systemd_saved_environment
    echo "WSL_INTEROP='$WSL_INTEROP'" >> $systemd_saved_environment
    echo "WSL_SYSTEMD_EXECUTION_ARGS='$WSL_SYSTEMD_EXECUTION_ARGS'" >> $systemd_saved_environment
    echo "PULSE_SERVER='$PULSE_SERVER'" >> $systemd_saved_environment
    echo "WAYLAND_DISPLAY='$WAYLAND_DISPLAY'" >> $systemd_saved_environment
end

function setup_interop
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

        set -e WAYLAND_DISPLAY
        if test -n "$SYSTEMD_PID"
            rm -f /run/user/(id -u)/wayland*
        end
        
        return
    end

    if test -n "$SSH_CONNECTION"
        return
    end

    # Check whether it is WSL1 or WSL2
    if test -n "$WSL_INTEROP"
        # Export an environment variable for helping other processes
        set -x WSL2 1
        
        if test -n "$DISPLAY"
            if test -n "$SYSTEMD_PID"
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
            set wsl2_d_tmp (grep </etc/resolv.conf nameserver | awk
