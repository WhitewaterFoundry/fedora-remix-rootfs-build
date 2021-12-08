#!/usr/bin/env bash

echo -n -e '\033]9;4;3;100\033\\'

BASE_URL="https://raw.githubusercontent.com/WhitewaterFoundry/fedora-remix-rootfs-build/master"
sha256sum /usr/local/bin/upgrade.sh >/tmp/sum.txt
sudo curl -L -f "${BASE_URL}/linux_files/upgrade.sh" -o /usr/local/bin/upgrade.sh
sudo chmod +x /usr/local/bin/upgrade.sh
sha256sum -c /tmp/sum.txt

CHANGED=$?
rm -r /tmp/sum.txt

# the script has changed? run the newer one
if [[ ${CHANGED} -eq 1 ]]; then
  echo Running the updated script
  bash /usr/local/bin/upgrade.sh
  exit 0
fi

sudo rm -f /etc/yum.repos.d/wslutilties.repo
sudo rm -f /var/lib/rpm/.rpm.lock
sudo dnf -y update --nogpgcheck
sudo rm -f /var/lib/rpm/.rpm.lock

# WSLU 3 is not installed
if [[ "$(wslsys -v | grep -c "v3\.")" -eq 0 ]]; then
  (
    source /etc/os-release && sudo dnf -y copr enable wslutilities/wslu "${ID_LIKE}"-"${VERSION_ID}"-"$(uname -m)"
  )
  sudo rm -f /var/lib/rpm/.rpm.lock
  sudo dnf -y update wslu --nogpgcheck
  sudo rm -f /var/lib/rpm/.rpm.lock
fi

# Update the release and main startup script files
sudo curl -L -f "${BASE_URL}/linux_files/00-remix.sh" -o /etc/profile.d/00-remix.sh
sudo mkdir -p /etc/fish/conf.d/
sudo curl -L -f "${BASE_URL}/linux_files/00-remix.fish" -o /etc/fish/conf.d/00-remix.fish

(
  source /etc/os-release
  sudo curl -L -f "${BASE_URL}/linux_files/os-release-${VERSION_ID}" -o /etc/os-release
)

# Add local.conf to fonts
sudo curl -L -f "${BASE_URL}/linux_files/local.conf" -o /etc/fonts/local.conf

# Fix a problem with the current WSL2 kernel
if [[ $( sudo dnf info --installed iproute | grep -c '5.8' ) == 0 ]]; then

  sudo dnf -y install --nogpgcheck 'dnf-command(versionlock)' > /dev/null 2>&1
  sudo dnf -y install --nogpgcheck iproute-5.8.0 > /dev/null 2>&1
  sudo dnf versionlock add iproute > /dev/null 2>&1
fi

# Install mesa
source /etc/os-release
if [[ -n ${WAYLAND_DISPLAY} && ${VERSION_ID} -ge 34 && $( sudo dnf info --installed mesa-libGL | grep -c '21.0.2-wsl' ) == 0 ]]; then
  sudo dnf versionlock delete mesa-dri-drivers mesa-libGL mesa-filesystem mesa-libglapi
  curl -s https://packagecloud.io/install/repositories/whitewaterfoundry/fedoraremix/script.rpm.sh | sudo env os=fedora dist=33 bash
  sudo dnf -y install --allowerasing --nogpgcheck mesa-dri-drivers-21.0.2-wsl.fc34.x86_64 mesa-libGL-21.0.2-wsl.fc34.x86_64 glx-utils
  sudo dnf versionlock add mesa-dri-drivers mesa-libGL mesa-filesystem mesa-libglapi
fi

if [[ $(sudo dnf -y copr list | grep -c "trustywolf/wslu") == 1 ]]; then
  (
    source /etc/os-release
    sudo dnf -y copr remove trustywolf/wslu "${ID_LIKE}"-"${VERSION_ID}"-"$(uname -m)"
    sudo dnf -y copr enable wslutilities/wslu "${ID_LIKE}"-"${VERSION_ID}"-"$(uname -m)"
  )
fi

if [[ -z ${WSL2} ]]; then
  gpgcheck_enabled=$(sudo dnf config-manager --dump '*' | grep -c "gpgcheck = 1")

  if [[ ${gpgcheck_enabled} -gt 0 ]]; then
    sudo curl -L -f "${BASE_URL}/linux_files/check-dnf.sh" -o /etc/profile.d/check-dnf.sh
    sudo curl -L -f "${BASE_URL}/linux_files/check-dnf.fish" -o /etc/fish/conf.d/check-dnf.fish
    sudo curl -L -f "${BASE_URL}/linux_files/check-dnf" -o /usr/bin/check-dnf
    echo '%wheel   ALL=NOPASSWD: /usr/bin/check-dnf' | sudo EDITOR='tee -a' visudo --quiet --file=/etc/sudoers.d/check-dnf
    sudo chmod -w /usr/bin/check-dnf
    sudo chmod u+x /usr/bin/check-dnf

    sudo check-dnf
  fi
fi

echo -n -e '\033]9;4;0;100\033\\'
