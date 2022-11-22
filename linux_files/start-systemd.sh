#!/bin/bash

#######################################
# Rebuilds the interop with Windows executables
# Globals:
#   WSL_INTEROP
# Arguments:
#  None
#######################################
function setup_interop() {
  # shellcheck disable=SC2155,SC2012
  # bashsupport disable=BP5006
  export WSL_INTEROP="$(ls -U /run/WSL/*_interop | tail -1)"
}

#######################################
#
# Globals:
#   HOME
#   PATH
#   PENGWIN_COMMAND
#   PENGWIN_REMOTE_DESKTOP
#   PULSE_SERVER
#   SUDO_USER
#   WSL_DISTRO_NAME
#   WSL_INTEROP
#   WSL_SYSTEMD_EXECUTION_ARGS
#   is_systemd_ready_cmd
#   sudo_user_home
#   systemd_exe
#   systemd_pid
#   wait_msg
# Arguments:
#  None
#######################################
function main() {
  if [ -z "${WSL_INTEROP}" ]; then
    echo "Error: start-systemd requires WSL 2."
    echo " -> Try upgrading your distribution to WSL 2."
    echo "Alternatively you can try wslsystemctl which provides basic functionality for WSL 1."
    echo " -> sudo wslsystemctl start <my-service-name>"
    echo
    echo "Press Enter to exit..."
    read -r
    exit 0
  fi

  # shellcheck disable=SC2155
  local systemd_exe="$(command -v systemd)"

  if [ -z "${systemd_exe}" ]; then
    if [ -x "/usr/lib/systemd/systemd" ]; then
      systemd_exe="/usr/lib/systemd/systemd"
    else
      systemd_exe="/lib/systemd/systemd"
    fi
  fi

  systemd_exe="${systemd_exe} --unit=multi-user.target" # snapd requires multi-user.target not basic.target

  # shellcheck disable=SC2155
  local systemd_pid="$(ps -C systemd -o pid= | head -n1)"
  # bashsupport disable=BP2001
  readonly systemd_environment=".systemd.env"
  # shellcheck disable=SC2155
  # bashsupport disable=BP2001
  export sudo_user_home="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"

  if [ -z "${systemd_pid}" ] || [ "${systemd_pid}" -ne 1 ]; then

    if [ -f "${sudo_user_home}/${systemd_environment}" ]; then
      set -a
      # shellcheck disable=SC1090
      . "${sudo_user_home}/${systemd_environment}"
      set +a

      setup_interop
    fi

    if [ -z "${systemd_pid}" ]; then
      env -i /usr/bin/unshare --fork --mount-proc --pid --propagation shared -- sh -c "
      mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
      exec ${systemd_exe}
      " &
      while [ -z "${systemd_pid}" ]; do
        systemd_pid="$(ps -C systemd -o pid= | head -n1)"
        sleep 1
      done
    fi

    local is_systemd_ready_cmd="/usr/bin/nsenter --mount --pid --target ${systemd_pid} -- systemctl is-system-running"
    # shellcheck disable=SC2155
    local wait_msg="$(${is_systemd_ready_cmd} 2>&1)"
    if [ "${wait_msg}" = "initializing" ] || [ "${wait_msg}" = "starting" ] || [ "${wait_msg}" = "Failed to connect to bus: No such file or directory" ]; then
      echo "Waiting for systemd to finish booting"
    fi
    while [ "${wait_msg}" = "initializing" ] || [ "${wait_msg}" = "starting" ] || [ "${wait_msg}" = "Failed to connect to bus: No such file or directory" ]; do
      echo -n "."
      sleep 1
      wait_msg="$(${is_systemd_ready_cmd} 2>&1)"
    done

    {
      echo "PATH='${PATH}'"
      echo "WSL_DISTRO_NAME='${WSL_DISTRO_NAME}'"
      echo "WSL_INTEROP='${WSL_INTEROP}'"
      echo "WSL_SYSTEMD_EXECUTION_ARGS='${WSL_SYSTEMD_EXECUTION_ARGS}'"
      echo "PULSE_SERVER='${PULSE_SERVER}'"
    } >"${sudo_user_home}/${systemd_environment}"
    chown "${SUDO_USER}:${SUDO_USER}" "${sudo_user_home}/${systemd_environment}"

    exec /usr/bin/nsenter --mount --pid --target "${systemd_pid}" -- sudo -u "${SUDO_USER}" /bin/sh -c "set -a; . '${sudo_user_home}/${systemd_environment}'; set +a; cd; $(getent passwd "${SUDO_USER}" | cut -d: -f7) --login"
  else
    exec sudo -u "${SUDO_USER}" /bin/sh -c "cd; $(getent passwd "${SUDO_USER}" | cut -d: -f7) --login"
  fi
}

main "$@"
