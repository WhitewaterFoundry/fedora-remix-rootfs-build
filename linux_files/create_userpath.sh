#!/bin/bash

#######################################
# Ensures the user's runtime directory exists under /run/user/<uid>.
# If the directory does not exist, it is created (parents included).
# Globals:
#   None
# Arguments:
#   uid: Numeric user ID whose runtime directory should exist.
# Returns:
#   Exit status of the final command executed:
#     - 0 if the directory already exists or was created successfully.
#     - Non-zero if directory creation fails.
# Side effects:
#   May create /run/user/<uid>.
#   Suppresses mkdir error output (stderr) to avoid noisy logs.
#######################################
function main() {
  local uid="${1}"

  local user_path="/run/user/${uid}"
  if [[ ! -d "${user_path}" ]]; then
    mkdir -p "${user_path}" 2>/dev/null
    chown -R "${uid}:${uid}" "${user_path}" 2>/dev/null

    # Take advantage of the superuser and try to create other possible missing directories when systemd is not running
    mkdir -p "/etc/xdg" 2>/dev/null
  fi
}

main "$@"
