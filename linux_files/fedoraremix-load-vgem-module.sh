#!/bin/bash
#
# fedoraremix-load-vgem-module - Load the Virtual Graphics Engine Module (vGEM) if not loaded
#
# This script checks if the vGEM kernel module is loaded and loads it if necessary.
# The vGEM module is used for virtual graphics acceleration in WSL2.
#
# Copyright 2025 hcram

# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
function main() {
  if ! lsmod | grep -q vgem; then
    modprobe vgem
  fi
}

main "$@"
