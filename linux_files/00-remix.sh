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
    if [ -n "$SYSTEMD_PID" ]; then
      rm -f /run/user/$(id -u)/wayland*
    fi
    
    return
  fi

  if [ -n "${SSH_CONNECTION}" ]; then
    return
  fi

  # check whether it is WSL1 or WSL2
  if [ -n "${WSL_INTEROP}" ]; then
    #Export an environment variable for helping other processes
    export WSL2=1
    
    if [ -n "${DISPLAY}" ]; then

      if [ -n "$SYSTEMD_PID" ]; then
        local uid="$(id -u)"
        
        ln -fs /mnt/wslg/runtime-dir/wayland-0 /run/user/${uid}/
        ln -fs /mnt/wslg/runtime-dir/wayland-0.lock /run/user/${uid}/
        ln -fs /mnt/wslg/runtime-dir/pulse /run/user/${uid}/pulse
      fi
    
      return
    fi

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

setup_dbus() {
  # if dbus-launch is installed then load it
  if ! (command -v dbus-launch >/dev/null); then
    return
  fi

  # Enabled via systemd
  if [ -n "${DBUS_SESSION_BUS_ADDRESS}" ]; then
    return
  fi

  dbus_pid="$(pidof dbus-daemon | cut -d' ' -f1)"

  if [ -z "${dbus_pid}" ]; then
    dbus_env="$(timeout 2s dbus-launch --auto-syntax)"
    eval "${dbus_env}"

    echo "${dbus_env}" >"/tmp/dbus_env_${DBUS_SESSION_BUS_PID}"

    unset dbus_env
  else # Running from a previous session
    eval "$(cat "/tmp/dbus_env_${dbus_pid}")"
  fi

  unset dbus_pid
}

setup_display
setup_dbus

# speed up some GUI apps like gedit
export NO_AT_BRIDGE=1

# Fix 'clear' scrolling issues
alias clear='clear -x'

# Custom aliases
alias ll='ls -al'
alias winget='powershell.exe winget'
alias wsl='wsl.exe'

if [ -n "${WSL2}" ]; then
  # Setup video acceleration
  export VDPAU_DRIVER=d3d12
  export LIBVA_DRIVER_NAME=d3d12

  # Setup Gallium Direct3D 12 driver
  export GALLIUM_DRIVER=d3d12
fi 

# Fix $PATH for Systemd
SYSTEMD_PID="$(ps -C systemd -o pid= | head -n1)"

if [ -z "$SYSTEMD_PID" ]; then

  save_environment

elif [ -n "$SYSTEMD_PID" ] && [ "$SYSTEMD_PID" -eq 1 ] && [ -f "$HOME/.systemd.env" ] && [ -n "$WSL_SYSTEMD_EXECUTION_ARGS" ]; then
  # Only if bult-in systemd was started
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
