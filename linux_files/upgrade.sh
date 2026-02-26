#!/usr/bin/env bash

echo -n -e '\033]9;4;3;100\033\\'

base_url="https://raw.githubusercontent.com/WhitewaterFoundry/fedora-remix-rootfs-build/master"
sudo curl -L -f "${base_url}/linux_files/upgrade.sh" -o /usr/local/bin/upgrade.sh
sudo chmod +x /usr/local/bin/upgrade.sh

# Do not change above this line to avoid update errors

if [[ ! -L /usr/local/bin/update.sh ]]; then
  sudo ln -s /usr/local/bin/upgrade.sh /usr/local/bin/update.sh
fi

# ----------------------------
# WSL detection helpers
# ----------------------------
function is_wsl1() {
  # Existing convention in this script: WSL2 env var empty => WSL1
  [[ -z "${WSL2:-}" ]]
}

function has_memfd() {
  # Fast capability check: returns 0 if memfd_create exists, non-zero otherwise
  python3 - <<'PY' >/dev/null 2>&1
import os
fd = os.memfd_create("t")
os.close(fd)
PY
}

function rpm_ver_lt() {
  # rpm_ver_lt <a> <b>  => true if a < b (rpm semantics)
  local result
  rpmdev-vercmp "$1" "$2" >/dev/null 2>&1
  result=$?
  [[ $result -eq 12 ]]
}

function fix_wsl1() {
  if is_wsl1; then
    sudo rm -f /var/lib/rpm/.rpm.lock
    # If WSL1 fix systemd upgrades
    if pushd /bin >/dev/null; then
      sudo mv -f systemd-sysusers{,.org}
      sudo ln -s echo systemd-sysusers
      popd >/dev/null || true
    fi
  fi
}

function dnf_install() {
  if is_wsl1; then
    sudo dnf -y install --nogpgcheck --no-best "$@"
  else
    sudo dnf -y install "$@"
  fi
}

function dnf_update() {
  if is_wsl1; then
    sudo dnf -y update --nogpgcheck --no-best "$@"
  else
    sudo dnf -y update "$@"
  fi
}

function dnf_downgrade() {
  if is_wsl1; then
    sudo dnf -y downgrade --nogpgcheck "$@"
  else
    sudo dnf -y downgrade "$@"
  fi
}

# ----------------------------
# WSL1 Pixbuf/Glycin workaround
# ----------------------------
function ensure_wsl1_pixbuf_compat() {
  source /etc/os-release || return 0

  # Only relevant for WSL1 + Fedora 43 where gdk-pixbuf 2.44 pulls glycin stack
  if ! is_wsl1; then
    return 0
  fi

  # If memfd exists, no need to do anything (future-proof)
  if has_memfd; then
    return 0
  fi

  # Scope guard: only enforce on Fedora 43 (expand to >=43 if needed)
  if [[ "${VERSION_ID}" != "43" ]]; then
    return 0
  fi

  # Ensure version comparison tooling exists
  if ! command -v rpmdev-vercmp >/dev/null 2>&1; then
    dnf_install rpmdevtools
  fi

  # Get installed gdk-pixbuf2 version-release
  local pixbuf_vr
  pixbuf_vr="$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' gdk-pixbuf2 2>/dev/null)"
  local rpm_rc=$?

  # Exit codes: 0 = installed, 1 = not installed, >1 = query error
  if [[ ${rpm_rc} -ne 0 && ${rpm_rc} -ne 1 ]]; then
    echo "Error: rpm query for gdk-pixbuf2 failed with status ${rpm_rc}. Aborting WSL1 pixbuf compatibility changes." >&2
    return "${rpm_rc}"
  fi

  # If not installed (empty pixbuf_vr), just install the pinned compatible version from WhitewaterFoundry repo
  if [[ -z "${pixbuf_vr}" ]]; then
    # Assumption: WhitewaterFoundry repo provides gdk-pixbuf2-2.42.* for fc43
    dnf_install --allowerasing gdk-pixbuf2-2.42\*
  else
    # If installed >= 2.44.0, downgrade to 2.42.* from WhitewaterFoundry repo
    if ! rpm_ver_lt "${pixbuf_vr}" "2.44.0-0"; then
      dnf_downgrade --allowerasing gdk-pixbuf2-2.42\*
    fi
  fi

  # Remove glycin stack if present (it triggers memfd usage paths)
  sudo dnf -y remove glycin-loaders glycin-libs glycin-thumbnailer glycin || true

  # Version lock to prevent drift during future updates
  dnf_install 'dnf-command(versionlock)'
  sudo dnf versionlock add gdk-pixbuf2 >/dev/null 2>&1 || true
  sudo dnf versionlock add glycin-loaders glycin-libs glycin-thumbnailer glycin >/dev/null 2>&1 || true

  # Optional: refresh loaders cache if present; non-fatal if missing
  if command -v gdk-pixbuf-query-loaders >/dev/null 2>&1; then
    sudo gdk-pixbuf-query-loaders --update-cache >/dev/null 2>&1 || true
  fi
}

sudo rm -f /etc/yum.repos.d/wslutilties.repo
fix_wsl1

# Run compat enforcement BEFORE and AFTER update:
ensure_wsl1_pixbuf_compat

dnf_update
fix_wsl1

ensure_wsl1_pixbuf_compat

# Remove old COPR wslu repositories for all Fedora versions
copr_found=false
for copr_file in /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:wslutilities:wslu*.repo; do
  if [[ -f "${copr_file}" ]]; then
    sudo rm -f "${copr_file}"
    copr_found=true
  fi
done

# WSLU 4 is not installed or COPR was found and removed
if [[ "$(wslsys -v | grep -c "v4\.")" -eq 0 ]] || [[ "${copr_found}" == true ]]; then
  (
    source /etc/os-release
    curl -s https://packagecloud.io/install/repositories/whitewaterfoundry/wslu/script.rpm.sh | sudo env os=fedora dist="${VERSION_ID}" bash
  )
  fix_wsl1
  dnf_update wslu
  fix_wsl1
fi

# Update the release and main startup script files
sudo curl -L -f "${base_url}/linux_files/00-remix.sh" -o /etc/profile.d/00-remix.sh
sudo mkdir -p /etc/fish/conf.d/
sudo curl -L -f "${base_url}/linux_files/00-remix.fish" -o /etc/fish/conf.d/00-remix.fish
sudo chmod -x,+r /etc/profile.d/00-remix.sh

(
  source /etc/os-release
  sudo curl -L -f "${base_url}/linux_files/os-release-${VERSION_ID}" -o /etc/os-release

  if [[ ${VERSION_ID} -eq '39' && ! -f /etc/profile.d/bash-color-prompt.sh ]]; then
    dnf_install bash-color-prompt
  fi
)
sudo curl -L -f "${base_url}/linux_files/bash-prompt-wsl.sh" -o /etc/profile.d/bash-prompt-wsl.sh

# Add local.conf to fonts
sudo curl -L -f "${base_url}/linux_files/local.conf" -o /etc/fonts/local.conf

# Install additional scripts
sudo curl -L -f "${base_url}/linux_files/install-desktop.sh" -o /usr/local/bin/install-desktop.sh
sudo chmod +x /usr/local/bin/install-desktop.sh

# Install mesa
source /etc/os-release

declare -a mesa_version=('24.1.2-7_wsl.fc40' '24.2.5-1_wsl_2.fc41' '25.0.4-2_wsl_3.fc42' '25.3.5-1_wsl.fc43')
declare -a target_version=('40' '41' '42' '43')
declare -i length=${#mesa_version[@]}

for ((i = 0; i < length; i++)); do
  if [[ ${VERSION_ID} -eq ${target_version[i]} && $(sudo dnf info --installed mesa-libGL | grep -c "${mesa_version[i]}") == 0 ]]; then

    sudo dnf versionlock delete mesa-dri-drivers mesa-libGL mesa-filesystem mesa-libglapi mesa-va-drivers mesa-vdpau-drivers mesa-libEGL mesa-libgbm mesa-libxatracker mesa-vulkan-drivers
    curl -s https://packagecloud.io/install/repositories/whitewaterfoundry/fedoraremix/script.rpm.sh | sudo env os=fedora dist="${VERSION_ID}" bash
    dnf_install --allowerasing mesa-dri-drivers-"${mesa_version[i]}" mesa-libGL-"${mesa_version[i]}" mesa-va-drivers-"${mesa_version[i]}" mesa-vdpau-drivers-"${mesa_version[i]}" mesa-libEGL-"${mesa_version[i]}" mesa-libgbm-"${mesa_version[i]}" mesa-libxatracker-"${mesa_version[i]}" mesa-vulkan-drivers-"${mesa_version[i]}" glx-utils vdpauinfo libva-utils
    sudo dnf versionlock add mesa-dri-drivers mesa-libGL mesa-filesystem mesa-libglapi mesa-va-drivers mesa-vdpau-drivers mesa-libEGL mesa-libgbm mesa-libxatracker mesa-vulkan-drivers
  fi
done

if [[ $(id | grep -c video) == 0 ]]; then
  sudo /usr/sbin/groupadd -g 44 wsl-video
  sudo /usr/sbin/usermod -aG wsl-video "$(whoami)"
  sudo /usr/sbin/usermod -aG video "$(whoami)"
  sudo /usr/sbin/usermod -aG render "$(whoami)"
fi

if [[ -f "/etc/profile.d/check-dnf.sh" ]]; then
  sudo rm /etc/profile.d/check-dnf.sh
  sudo rm /etc/fish/conf.d/check-dnf.fish
fi

# Upgrade Systemd
sudo curl -L -f "${base_url}/linux_files/start-systemd.sudoers" -o /etc/sudoers.d/start-systemd
sudo curl -L -f "${base_url}/linux_files/start-systemd.sh" -o /usr/local/bin/start-systemd

# Configure vgem module loading
sudo curl -L -f "${base_url}/linux_files/fedoraremix-load-vgem-module.sudoers" -o /etc/sudoers.d/fedoraremix-load-vgem-module
sudo curl -L -f "${base_url}/linux_files/fedoraremix-load-vgem-module.sh" -o /usr/local/bin/fedoraremix-load-vgem-module
sudo chmod +x /usr/local/bin/fedoraremix-load-vgem-module

# Add create_userpath script
sudo curl -L -f "${base_url}/linux_files/create_userpath.sudoers" -o /etc/sudoers.d/create_userpath
sudo curl -L -f "${base_url}/linux_files/create_userpath.sh" -o /usr/local/bin/create_userpath
sudo chmod +x /usr/local/bin/create_userpath

# Remove conflicting services
if [ -f /etc/systemd/system/wsl2-xwayland.service ]; then
  sudo rm -f /etc/systemd/system/wsl2-xwayland.service
  sudo rm -f /etc/systemd/system/wsl2-xwayland.socket
  sudo rm -f /etc/systemd/system/sockets.target.wants/wsl2-xwayland.socket
fi

# Mask conflicting services
sudo ln -sf /dev/null /etc/systemd/system/systemd-resolved.service
sudo ln -sf /dev/null /etc/systemd/system/systemd-networkd.service
sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-setup.service
sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-clean.service
sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-clean.timer
sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-setup-dev-early.service
sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-setup-dev.service
sudo ln -sf /dev/null /etc/systemd/system/tmp.mount
sudo ln -sf /dev/null /etc/systemd/system/NetworkManager.service
sudo ln -sf /dev/null /etc/systemd/system/NetworkManager-wait-online.service

sudo curl -L -f "${base_url}/linux_files/systemctl3.py" -o /usr/local/bin/wslsystemctl
sudo curl -L -f "${base_url}/linux_files/journalctl3.py" -o /usr/local/bin/wsljournalctl
sudo chmod u+x /usr/local/bin/start-systemd
sudo chmod +x /usr/local/bin/wslsystemctl
sudo chmod +x /usr/local/bin/wsljournalctl

echo -n -e '\033]9;4;0;100\033\\'
