#!/bin/sh

# Only the default WSL user should run this script
if ! (id -Gn | grep -c "adm.*wheel\|wheel.*adm" >/dev/null); then
  return
fi

if [ -z "${WSL2}" ]; then
  sudo check-dnf
fi
