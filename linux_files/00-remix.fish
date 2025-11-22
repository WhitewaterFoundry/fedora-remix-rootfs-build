#!/usr/bin/fish

# Only the default WSL user should run this script
if not id -Gn | string match -rq 'adm.*wheel|wheel.*adm'
    exit
end

if test -n "$XRDP_SESSION"
    exit
end

if test -n "$SSH_CONNECTION"
    exit
end

# check whether it is WSL1 for WSL2
if test -n "$WSL_INTEROP"
    #Export an enviroment variable for helping other processes
    set --export WSL2 1

    if test -n "$DISPLAY"
        # WSLg support - setup /run/user directory and symlinks
        set uid (id -u)
        set user_path "/run/user/$uid"
        
        if not test -d "$user_path"
            sudo /usr/local/bin/create_userpath $uid 2>/dev/null
        end
        
        set wslg_runtime_dir "/mnt/wslg/runtime-dir"
        
        ln -fs "$wslg_runtime_dir/wayland-0" "$user_path/" 2>/dev/null
        ln -fs "$wslg_runtime_dir/wayland-0.lock" "$user_path/" 2>/dev/null
        
        set pulse_path "$user_path/pulse"
        set wslg_pulse_dir "$wslg_runtime_dir/pulse"
        
        if not test -d "$pulse_path"
            mkdir -p "$pulse_path" 2>/dev/null
            ln -fs "$wslg_pulse_dir/native" "$pulse_path/" 2>/dev/null
            ln -fs "$wslg_pulse_dir/pid" "$pulse_path/" 2>/dev/null
        else if test -S "$pulse_path/native"
            rm -f "$pulse_path/native" 2>/dev/null
            ln -s "$wslg_pulse_dir/native" "$pulse_path/" 2>/dev/null
        end
        
        set -e uid
        set -e user_path
        set -e wslg_runtime_dir
        set -e wslg_pulse_dir
        set -e pulse_path
    else
        # enable external x display for WSL 2
        set route_exec (wslpath 'C:\Windows\system32\route.exe')
        if command -q route.exe
            set route_exec (command -s route.exe)
        end

        set wsl2_d_tmp (eval "$route_exec print 2>/dev/null" | grep 0.0.0.0 | head -1 | awk '{print $4}')

        if test -n "$wsl2_d_tmp"
            set --export DISPLAY "$wsl2_d_tmp:0"
        else
            set wsl2_d_tmp (ip route | grep default | awk '{print $3; exit;}')
            set --export DISPLAY "$wsl2_d_tmp:0"
        end

        set -e wsl2_d_tmp
        set -e route_exec
    end
    
    # Setup video acceleration
    set --export VDPAU_DRIVER d3d12
    set --export LIBVA_DRIVER_NAME d3d12
    set --export GALLIUM_DRIVER d3d12
else
    # enable external x display for WSL 1
    set --export DISPLAY "localhost:0"
end

# if dbus-launch is installed then load it
if command -q dbus-launch
    set -x DBUS_SESSION_BUS_ADDRESS (timeout 2s dbus-launch sh -c 'echo "$DBUS_SESSION_BUS_ADDRESS"')
end

# speed up some GUI apps like gedit
set --export NO_AT_BRIDGE 1

# Fix 'clear' scrolling issues
alias clear='clear -x'

# Check if we have Windows Path
if command -q cmd.exe

    # Create a symbolic link to the windows home

    # Here have a issue: %HOMEDRIVE% might be using a custom set location
    # moving cmd to where Windows is installed might help: %SYSTEMDRIVE%
    set wHomeWinPath (cmd.exe /c 'cd %SYSTEMDRIVE%\ && echo %HOMEDRIVE%%HOMEPATH%' 2>/dev/null | string replace -a \r '')

    # shellcheck disable=SC2155
    set --export WIN_HOME (wslpath -u $wHomeWinPath)

    set win_home_lnk "$HOME/winhome"
    if test ! -e "$win_home_lnk"
        ln -s -f "$WIN_HOME" "$win_home_lnk" &>/dev/null
    end

    set -e win_home_lnk

end
