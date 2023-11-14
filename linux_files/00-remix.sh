#!/bin/sh
# bashsupport disable=BP5007

# Only the default WSL user should run this script
if ! (id -Gn | grep -c "adm.*wheel\|wheel.*adm" >/dev/null); then
  return
fi

systemd_saved_environment="$HOME/.systemd.env"

save_environment() {
  {
    echo "PATH='$PATH'"
    echo "WSL_DISTRO_NAME='$WSL_DISTRO_NAME'"
    echo "WSL_INTEROP='$WSL_INTEROP'"
    echo "WSL_SYSTEMD_EXECUTION_ARGS='$WSL_SYSTEMD_EXECUTION_ARGS'"
    echo "PULSE_SERVER='$PULSE_SERVER'"
  } >"${systemd_saved_environment}"
}

setup_interop() {
  # shellcheck disable=SC2155,SC2012
  export WSL_INTEROP="$(ls -U /run/WSL/*_interop | tail -1)"
}

setup_display() {
  if [ -n "${XRDP_SESSION}" ]; then
    if [ -f "${systemd_saved_environment}" ]; then
      set -a
      # shellcheck disable=SC1090
      . "${systemd_saved_environment}"
      set +a
    fi

    if [ -n "${WSL_INTEROP}" ]; then
      export WSL2=1

      setup_interop
    fi

    unset WAYLAND_DISPLAY
    rm -f /mnt/wslg/runtime-dir/wayland*

    return
  fi

  if [ -n "${SSH_CONNECTION}" ]; then
    return
  fi

  # check whether it is WSL1 or WSL2
  if [ -n "${WSL_INTEROP}" ]; then
    if [ -n "${DISPLAY}" ]; then
      #Export an environment variable for helping other processes
      export WSL2=1

      return
    fi
    #Export an environment variable for helping other processes
    export WSL2=1
    # enable external x display for WSL 2

    ipconfig_exec=$(wslpath "C:\\Windows\\System32\\ipconfig.exe")
    if (command -v ipconfig.exe >/dev/null 2>&1); then
      ipconfig_exec=$(command -v ipconfig.exe)
    fi

    wsl2_d_tmp="$(eval "$ipconfig_exec 2> /dev/null" | grep -n -m 1 "Default Gateway.*: [0-9a-z]" | cut -d : -f 1)"

    if [ -n "${wsl2_d_tmp}" ]; then

      wsl2_d_tmp="$(eval "$ipconfig_exec" | sed "$((wsl2_d_tmp - 4))"','"$((wsl2_d_tmp + 0))"'!d' | grep IPv4 | cut -d : -f 2 | sed -e "s|\s||g" -e "s|\r||g")"
      export DISPLAY=${wsl2_d_tmp}:0
    else
      wsl2_d_tmp="$(grep </etc/resolv.conf nameserver | awk '{print $2}')"
      export DISPLAY=${wsl2_d_tmp}:0
    fi

    unset wsl2_d_tmp
    unset ipconfig_exec
  else
    # enable external x display for WSL 1
    export DISPLAY=localhost:0

    # Export an environment variable for helping other processes
    unset WSL2
  fi
}

setup_display

# if dbus-launch is installed then load it
if (command -v dbus-launch >/dev/null 2>&1); then
  eval "$(timeout 2s dbus-launch --auto-syntax)"
fi

# speed up some GUI apps like gedit
export NO_AT_BRIDGE=1
export PS1='\[\033]133;D;$?\]\[\033\\\033]133;A\033\\\]\[\e[${PROMPT_COLOR:-32}m\]\u@\h\[\e[0m\]:\[\e[${PROMPT_COLOR:-32}m\]\w\[\033]9;9;"$(wslpath -w "${PWD}")"\033\\\]\[\e[0;31m\]${?#0}\[\e[0m\]\$ \[\033]133;B\033\\\]'

# Fix 'clear' scrolling issues
alias clear='clear -x'

# Custom aliases
alias ll='ls -al'
alias winget='powershell.exe winget'
alias wsl='wsl.exe'

#Setup video acceleration
export VDPAU_DRIVER=d3d12
export LIBVA_DRIVER_NAME=d3d12

# Fix $PATH for Systemd
SYSTEMD_PID="$(ps -C systemd -o pid= | head -n1)"

if [ -z "$SYSTEMD_PID" ]; then

  save_environment

elif [ -n "$SYSTEMD_PID" ] && [ "$SYSTEMD_PID" -eq 1 ] && [ -f "$HOME/.systemd.env" ]; then
  set -a
  # shellcheck disable=SC1090
  . "${systemd_saved_environment}"
  set +a

  setup_interop
fi

# Check if we have Windows Path
if [ -z "$WIN_HOME" ] && (command -v cmd.exe >/dev/null 2>&1); then

  # Create a symbolic link to the windows home

  # Here have a issue: %HOMEDRIVE% might be using a custom set location
  # moving cmd to where Windows is installed might help: %SYSTEMDRIVE%
  wHomeWinPath=$(cmd.exe /c 'cd %SYSTEMDRIVE%\ && echo %HOMEDRIVE%%HOMEPATH%' 2>/dev/null | tr -d '\r')

  if [ ${#wHomeWinPath} -le 3 ]; then #wHomeWinPath contains something like H:\
    wHomeWinPath=$(cmd.exe /c 'cd %SYSTEMDRIVE%\ && echo %USERPROFILE%' 2>/dev/null | tr -d '\r')
  fi

  # shellcheck disable=SC2155
  export WIN_HOME="$(wslpath -u "${wHomeWinPath}")"

  win_home_lnk=${HOME}/winhome
  if [ ! -e "${win_home_lnk}" ]; then
    ln -s -f "${WIN_HOME}" "${win_home_lnk}" >/dev/null 2>&1
  fi

  unset win_home_lnk

fi
