#!/bin/sh
# bashsupport disable=BP5007

save_environment() {
  {
    [ -n "${PATH}" ] && echo "PATH='$PATH'"
    [ -n "${WSL_DISTRO_NAME}" ] && echo "WSL_DISTRO_NAME='$WSL_DISTRO_NAME'"
    [ -n "${WSL_INTEROP}" ] && echo "WSL_INTEROP='$WSL_INTEROP'"
    [ -n "${WSL_SYSTEMD_EXECUTION_ARGS}" ] && echo "WSL_SYSTEMD_EXECUTION_ARGS='$WSL_SYSTEMD_EXECUTION_ARGS'"
    [ -n "${PULSE_SERVER}" ] && echo "PULSE_SERVER='$PULSE_SERVER'"
    [ -n "${WAYLAND_DISPLAY}" ] && echo "WAYLAND_DISPLAY='$WAYLAND_DISPLAY'"
  } >"${systemd_saved_environment}"
}

setup_interop() {
  # shellcheck disable=SC2155,SC2012
  export WSL_INTEROP="$(ls -U /run/WSL/*_interop | tail -1)"
}

define_xdg_environment() {
  # XDG Base Directory Specification
  # https://specifications.freedesktop.org/basedir/latest/

  if [ -z "${XDG_DATA_HOME}" ]; then
    export XDG_DATA_HOME="${HOME}/.local/share"
  fi
  mkdir -p "${XDG_DATA_HOME}" 2>/dev/null || true

  if [ -z "${XDG_CONFIG_HOME}" ]; then
    export XDG_CONFIG_HOME="${HOME}/.config"
  fi
  mkdir -p "${XDG_CONFIG_HOME}" 2>/dev/null || true

  if [ -z "${XDG_STATE_HOME}" ]; then
    export XDG_STATE_HOME="${HOME}/.local/state"
  fi
  mkdir -p "${XDG_STATE_HOME}" 2>/dev/null || true

  if [ -z "${XDG_CACHE_HOME}" ]; then
    export XDG_CACHE_HOME="${HOME}/.cache"
  fi
  mkdir -p "${XDG_CACHE_HOME}" 2>/dev/null || true

  if [ -z "${XDG_DATA_DIRS}" ]; then
    export XDG_DATA_DIRS="/usr/local/share:/usr/share"
  fi

  if [ -z "${XDG_CONFIG_DIRS}" ]; then
    export XDG_CONFIG_DIRS="/etc/xdg"
  fi
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
      rm -f /run/user/"$(id -u)"/wayland* 2>/dev/null
    fi

    if [ -z "${PULSE_SERVER}" ]; then
      pulseaudio --enable-memfd=FALSE --disable-shm=TRUE --log-target=syslog --start >/dev/null 2>&1
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
      uid="$(id -u)"

      user_path="/run/user/${uid}"
      if [ ! -d "${user_path}" ]; then
        sudo /usr/local/bin/create_userpath "${uid}" 2>/dev/null
      fi

      if [ -z "$SYSTEMD_PID" ]; then
        export XDG_RUNTIME_DIR="${user_path}"
      fi

      wslg_runtime_dir="/mnt/wslg/runtime-dir"

      ln -fs "${wslg_runtime_dir}"/wayland-0 "${user_path}"/ 2>/dev/null
      ln -fs "${wslg_runtime_dir}"/wayland-0.lock "${user_path}"/ 2>/dev/null

      pulse_path="${user_path}/pulse"
      wslg_pulse_dir="${wslg_runtime_dir}"/pulse

      if [ ! -d "${pulse_path}" ]; then
        mkdir -p "${pulse_path}" 2>/dev/null

        ln -fs "${wslg_pulse_dir}"/native "${pulse_path}"/ 2>/dev/null
        ln -fs "${wslg_pulse_dir}"/pid "${pulse_path}"/ 2>/dev/null

      elif [ -S "${pulse_path}/native" ]; then
        # Handle stale socket: remove it and recreate as symlink to WSLg pulse
        rm -f "${pulse_path}/native" 2>/dev/null
        ln -fs "${wslg_pulse_dir}"/native "${pulse_path}"/ 2>/dev/null
      fi

      unset user_path
      unset wslg_runtime_dir
      unset wslg_pulse_dir
      unset pulse_path
      unset uid

      return
    fi

    # enable external x display for WSL 2
    route_exec=$(wslpath 'C:\Windows\system32\route.exe')

    if route_exec_path=$(command -v route.exe 2>/dev/null); then
      route_exec="${route_exec_path}"
    fi

    wsl2_d_tmp="$(eval "$route_exec print 2> /dev/null" | grep -a 0.0.0.0 | head -1 | awk '{print $4}')"

    if [ -n "${wsl2_d_tmp}" ]; then
      export DISPLAY="${wsl2_d_tmp}":0
    else
      wsl2_d_tmp="$(ip route | grep default | awk '{print $3; exit;}')"
      export DISPLAY="${wsl2_d_tmp}":0
    fi

    unset wsl2_d_tmp
    unset route_exec
  else
    # enable external x display for WSL 1
    export DISPLAY=localhost:0

    # Export an environment variable for helping other processes
    unset WSL2
  fi
}

setup_dbus() {
  # if dbus-launch is installed, then load it
  if ! (command -v dbus-launch >/dev/null); then
    return
  fi

  # Enabled via systemd
  if [ -n "${DBUS_SESSION_BUS_ADDRESS}" ]; then
    return
  fi

  # Use a per-user directory for storing the D-Bus environment
  dbus_env_dir="${XDG_RUNTIME_DIR:-${HOME}/.cache}"
  mkdir -p "${dbus_env_dir}" 2>/dev/null || true

  dbus_pid="$(pidof -s dbus-daemon)"

  if [ -z "${dbus_pid}" ]; then
    dbus_env="$(timeout 2s dbus-launch --auto-syntax)" || return

    # Extract and export only the expected variables from dbus-launch output
    DBUS_SESSION_BUS_ADDRESS="$(printf '%s\n' "${dbus_env}" | sed -n "s/^DBUS_SESSION_BUS_ADDRESS='\(.*\)';$/\1/p")"
    DBUS_SESSION_BUS_PID="$(printf '%s\n' "${dbus_env}" | sed -n "s/^DBUS_SESSION_BUS_PID=\([0-9][0-9]*\);$/\1/p")"

    if [ -n "${DBUS_SESSION_BUS_ADDRESS}" ] && [ -n "${DBUS_SESSION_BUS_PID}" ]; then
      export DBUS_SESSION_BUS_ADDRESS
      export DBUS_SESSION_BUS_PID

      dbus_env_file="${dbus_env_dir}/dbus_env_${DBUS_SESSION_BUS_PID}"
      {
        echo "DBUS_SESSION_BUS_ADDRESS='${DBUS_SESSION_BUS_ADDRESS}'"
        echo "DBUS_SESSION_BUS_PID='${DBUS_SESSION_BUS_PID}'"
      } >"${dbus_env_file}"
      chmod 600 "${dbus_env_file}" 2>/dev/null || true
    fi

    unset dbus_env
  else
    # Reuse existing dbus session
    dbus_env_file="${dbus_env_dir}/dbus_env_${dbus_pid}"
    if [ -f "${dbus_env_file}" ]; then
      DBUS_SESSION_BUS_ADDRESS="$(sed -n "s/^DBUS_SESSION_BUS_ADDRESS='\(.*\)'$/\1/p" "${dbus_env_file}")"
      DBUS_SESSION_BUS_PID="$(sed -n "s/^DBUS_SESSION_BUS_PID='\([0-9][0-9]*\)'$/\1/p" "${dbus_env_file}")"
      if [ -n "${DBUS_SESSION_BUS_ADDRESS}" ] && [ -n "${DBUS_SESSION_BUS_PID}" ]; then
        export DBUS_SESSION_BUS_ADDRESS
        export DBUS_SESSION_BUS_PID
      fi
    fi
  fi

  unset dbus_pid
  unset dbus_env_file
  unset dbus_env_dir
}

main() {
  # Only the default WSL user should run this script
  if ! (id -Gn | grep -c "adm.*wheel\|wheel.*adm" >/dev/null); then
    return
  fi

  systemd_saved_environment="$HOME/.systemd.env"

  SYSTEMD_PID="$(ps -C systemd -o pid= | head -n1)"

  define_xdg_environment

  setup_display

  if [ -z "$SYSTEMD_PID" ] && [ -z "${DBUS_SESSION_BUS_ADDRESS}" ]; then
    setup_dbus
  fi

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
    sudo /usr/local/bin/fedoraremix-load-vgem-module

    # Setup Gallium Direct3D 12 driver
    export GALLIUM_DRIVER=d3d12
  fi

  if [ -z "$SYSTEMD_PID" ]; then
    save_environment
  elif [ -n "$SYSTEMD_PID" ] && [ "$SYSTEMD_PID" -eq 1 ] && [ -f "$HOME/.systemd.env" ] &&
    [ -n "$WSL_SYSTEMD_EXECUTION_ARGS" ]; then
    # Only if built-in systemd was started
    set -a
    # shellcheck disable=SC1090
    . "${systemd_saved_environment}"
    set +a

    setup_interop
  fi

  # Check if we have Windows Path
  if [ -z "$WIN_HOME" ] && (command -v cmd.exe >/dev/null 2>&1); then

    # Create a symbolic link to the window's home

    # Here has an issue: %HOMEDRIVE% might be using a custom set location
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
  unset systemd_saved_environment
}

main "$@"
