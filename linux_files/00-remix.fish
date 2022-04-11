#!/usr/bin/fish

# Only the default WSL user should run this script
if not id -Gn | string match -rq 'adm.*wheel|wheel.*adm'
    exit
end

if test -n "$XRDP_SESSION"
    exit
end

# check whether it is WSL1 for WSL2
if test -n "$WSL_INTEROP"
    #Export an enviroment variable for helping other processes
    set --export WSL2 1

    if test -z "$DISPLAY"
        # enable external x display for WSL 2

        set ipconfig_exec (wslpath 'C:\Windows\System32\ipconfig.exe')
        if command -q ipconfig.exe
            set ipconfig_exec (command -s ipconfig.exe)
        end

        set wsl2_d_tmp ($ipconfig_exec 2>/dev/null | grep -n -m 1 "Default Gateway.*: [0-9a-z]" | cut -d : -f 1)

        if test -n "$wsl2_d_tmp"

            set wsl2_d_tmp ($ipconfig_exec 2>/dev/null | sed (math $wsl2_d_tmp - 4)','(math $wsl2_d_tmp + 0)'!d' | string replace -fr '^.*IPv4.*:\s*(\S+).*$' '$1')
            set --export DISPLAY "$wsl2_d_tmp:0"
        else
            set wsl2_d_tmp (grep nameserver /etc/resolv.conf | awk '{print $2}')
            set --export DISPLAY $wsl2_d_tmp:0
        end

        set -e wsl2_d_tmp
        set -e ipconfig_exec
    end
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
