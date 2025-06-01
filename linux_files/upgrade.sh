#!/usr/bin/env bash

echo -n -e '\033]9;4;3;100\033\\'

base_url="https://raw.githubusercontent.com/WhitewaterFoundry/fedora-remix-rootfs-build/master"
sudo curl -L -f "${base_url}/linux_files/upgrade.sh" -o /usr/local/bin/upgrade.sh
sudo chmod +x /usr/local/bin/upgrade.sh


# Do not change above this line to avoid update errors

if [[ ! -L /usr/local/bin/update.sh  ]]; then
  sudo ln -s /usr/local/bin/upgrade.sh /usr/local/bin/update.sh
fi

sudo rm -f /etc/yum.repos.d/wslutilties.repo
sudo rm -f /var/lib/rpm/.rpm.lock
sudo dnf -y update --nogpgcheck
sudo rm -f /var/lib/rpm/.rpm.lock

# WSLU 4 is not installed
if [[ "$(wslsys -v | grep -c "v4\.")" -eq 0 ]]; then
  (
    source /etc/os-release && sudo dnf -y copr enable wslutilities/wslu "${ID_LIKE}"-"${VERSION_ID}"-"$(uname -m)"
  )
  sudo rm -f /var/lib/rpm/.rpm.lock
  sudo dnf -y update wslu --nogpgcheck
  sudo rm -f /var/lib/rpm/.rpm.lock
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
    sudo dnf -y install --nogpgcheck bash-color-prompt
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

declare -a mesa_version=('24.1.2-7_wsl.fc40' '24.2.5-1_wsl_2.fc41' '25.0.4-2_wsl_3.fc42')
declare -a target_version=('40' '41' '42')
declare -i length=${#mesa_version[@]}

for (( i = 0; i < length; i++ )); do
  if [[ ${VERSION_ID} -eq ${target_version[i]} && $( sudo dnf info --installed mesa-libGL | grep -c "${mesa_version[i]}" ) == 0 ]]; then

    sudo dnf versionlock delete mesa-dri-drivers mesa-libGL mesa-filesystem mesa-libglapi mesa-va-drivers mesa-vdpau-drivers mesa-libEGL mesa-libgbm mesa-libxatracker mesa-vulkan-drivers
    curl -s https://packagecloud.io/install/repositories/whitewaterfoundry/fedoraremix/script.rpm.sh | sudo env os=fedora dist="${VERSION_ID}" bash
    sudo dnf -y install --allowerasing --nogpgcheck mesa-dri-drivers-"${mesa_version[i]}" mesa-libGL-"${mesa_version[i]}" mesa-va-drivers-"${mesa_version[i]}" mesa-vdpau-drivers-"${mesa_version[i]}" mesa-libEGL-"${mesa_version[i]}" mesa-libgbm-"${mesa_version[i]}" mesa-libxatracker-"${mesa_version[i]}" mesa-vulkan-drivers-"${mesa_version[i]}" glx-utils vdpauinfo libva-utils
    sudo dnf versionlock add mesa-dri-drivers mesa-libGL mesa-filesystem mesa-libglapi mesa-va-drivers mesa-vdpau-drivers mesa-libEGL mesa-libgbm mesa-libxatracker mesa-vulkan-drivers
  fi
done

if [[ $(id | grep -c video) == 0 ]]; then
  sudo /usr/sbin/groupadd -g 44 wsl-video
  sudo /usr/sbin/usermod -aG wsl-video "$(whoami)"
  sudo /usr/sbin/usermod -aG video "$(whoami)"
fi

if [[ $(sudo dnf -y copr list | grep -c "wslutilities/wslu") == 0 ]]; then
  (
    source /etc/os-release

    if [[ ${VERSION_ID} -gt 41 ]]; then
      sudo dnf -y copr enable wslutilities/wslu "${ID_LIKE}"-41-"$(uname -m)"
    else
      sudo dnf -y copr enable wslutilities/wslu "${ID_LIKE}"-"${VERSION_ID}"-"$(uname -m)"
    fi
  )
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

if [ -f /etc/systemd/system/wsl2-xwayland.service ]; then
  sudo rm -f /etc/systemd/system/wsl2-xwayland.service
  sudo rm -f /etc/systemd/system/wsl2-xwayland.socket
  sudo rm -f /etc/systemd/system/sockets.target.wants/wsl2-xwayland.socket
fi

# Mask conflicting services
sudo ln -sf /dev/null /etc/systemd/system/systemd-resolved.service
sudo ln -sf /dev/null /etc/systemd/system/systemd-networkd.service
sudo ln -sf /dev/null /etc/systemd/system/NetworkManager.service
sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-setup.service
sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-clean.service
sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-clean.timer
sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-setup-dev-early.service
sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-setup-dev.service
sudo ln -sf /dev/null /etc/systemd/system/tmp.mount

sudo curl -L -f "${base_url}/linux_files/systemctl3.py" -o /usr/local/bin/wslsystemctl
sudo curl -L -f "${base_url}/linux_files/journalctl3.py" -o /usr/local/bin/wsljournalctl
sudo chmod u+x /usr/local/bin/start-systemd
sudo chmod +x /usr/local/bin/wslsystemctl
sudo chmod +x /usr/local/bin/wsljournalctl

echo -n -e '\033]9;4;0;100\033\\'
