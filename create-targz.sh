#!/bin/bash
# bashsupport disable=BP5004


#######################################
# description
# Globals:
#   TMPDIR
#   version_id
#   arch
#   arch_dir
#   origin_dir
# Arguments:
#  None
#######################################
function build() {
  echo "##[section] Install dependencies"
  dnf -y update
  dnf -y install mock qemu-user-static
  if [ "$(uname -i)" != "$arch" ]; then
    systemctl restart systemd-binfmt.service
  fi

  echo "##[section] Move to our temporary directory"
  cd "${TMPDIR}"
  mkdir "${TMPDIR}"/dist

  echo "##[section] Make sure /dev is created before later mount"
  mkdir -m 0755 "${TMPDIR}"/dist/dev

  echo "##[section] Use mock to initialize chroot filesystem"
  mock --root="fedora-${version_id}-${arch}" --init --forcearch="${arch}" --rootdir="${TMPDIR}"/dist

  echo "##[section] Bind mount current /dev to new chroot/dev"
  # (fixes '/dev/null: Permission denied' errors)
  mount --bind /dev "${TMPDIR}"/dist/dev

  echo "##[section] Install required packages, exclude unnecessary packages to reduce image size"
  dnf --installroot="${TMPDIR}"/dist --forcearch="${arch}" --releasever="${version_id}" -y install @core libgcc glibc-langpack-en bash-color-prompt --exclude=grub\*,sssd-kcm,sssd-common,sssd-client,linux-firmware,dracut*,plymouth,parted,e2fsprogs,iprutils,iptables,ppc64-utils,selinux-policy*,policycoreutils,sendmail,kernel*,firewalld,fedora-release,fedora-logos,fedora-release-notes --allowerasing

  echo "##[section] Unmount /dev"
  umount "${TMPDIR}"/dist/dev

  mkdir -p "${TMPDIR}"/dist/etc/fish/conf.d/
  mkdir -p "${TMPDIR}"/dist/etc/fonts/
  mkdir -p "${TMPDIR}"/dist/usr/local/bin/

  echo "##[section] Fix dnf.conf"
  # shellcheck disable=SC2155
  local from_index=$(grep -n -m 1 '\[main\]' "${TMPDIR}"/dist/etc/dnf/dnf.conf | cut -d : -f 1)
  # shellcheck disable=SC2155
  local to_index=$(grep -n -m 1 '# repos' "${TMPDIR}"/dist/etc/dnf/dnf.conf | cut -d : -f 1)
  sed -i "${from_index}"','"$((to_index - 2))"'d' "${TMPDIR}"/dist/etc/dnf/dnf.conf

  cat "${origin_dir}"/linux_files/dnf.conf "${TMPDIR}"/dist/etc/dnf/dnf.conf >"${TMPDIR}"/dist/etc/dnf/dnf.temp
  mv "${TMPDIR}"/dist/etc/dnf/dnf.temp "${TMPDIR}"/dist/etc/dnf/dnf.conf

  echo "##[section] Copy over some of our custom files"
  cp "${origin_dir}"/linux_files/wsl.conf "${TMPDIR}"/dist/etc/
  cp "${origin_dir}"/linux_files/local.conf "${TMPDIR}"/dist/etc/fonts/
  cp "${origin_dir}"/linux_files/00-remix.sh "${TMPDIR}"/dist/etc/profile.d/
  cp "${origin_dir}"/linux_files/bash-prompt-wsl.sh "${TMPDIR}"/dist/etc/profile.d/
  cp "${origin_dir}"/linux_files/00-remix.fish "${TMPDIR}"/dist/etc/fish/conf.d/
  chmod -x,+r "${TMPDIR}"/dist/etc/profile.d/00-remix.sh
  chmod -x,+r "${TMPDIR}"/dist/etc/fish/conf.d/00-remix.fish
  chmod -x,+r "${TMPDIR}"/dist/etc/profile.d/bash-prompt-wsl.sh

  cp "${origin_dir}"/linux_files/upgrade.sh "${TMPDIR}"/dist/usr/local/bin/
  chmod +x "${TMPDIR}"/dist/usr/local/bin/upgrade.sh
  ln -s /usr/local/bin/upgrade.sh "${TMPDIR}"/dist/usr/local/bin/update.sh

  cp "${origin_dir}"/linux_files/install-desktop.sh "${TMPDIR}"/dist/usr/local/bin/install-desktop.sh
  chmod +x "${TMPDIR}"/dist/usr/local/bin/install-desktop.sh

  cp "${origin_dir}"/linux_files/start-systemd.sudoers "${TMPDIR}"/dist/etc/sudoers.d/start-systemd
  cp "${origin_dir}"/linux_files/start-systemd.sh "${TMPDIR}"/dist/usr/local/bin/start-systemd
  chmod +x "${TMPDIR}"/dist/usr/local/bin/start-systemd

  cp "${origin_dir}"/linux_files/fedoraremix-load-vgem-module.sudoers "${TMPDIR}"/dist/etc/sudoers.d/fedoraremix-load-vgem-module
  cp "${origin_dir}"/linux_files/fedoraremix-load-vgem-module.sh "${TMPDIR}"/dist/usr/local/bin/fedoraremix-load-vgem-module
  chmod +x "${TMPDIR}"/dist/usr/local/bin/fedoraremix-load-vgem-module

  cp "${origin_dir}"/linux_files/create_userpath.sudoers "${TMPDIR}"/dist/etc/sudoers.d/create_userpath
  cp "${origin_dir}"/linux_files/create_userpath.sh "${TMPDIR}"/dist/usr/local/bin/create_userpath
  chmod +x "${TMPDIR}"/dist/usr/local/bin/create_userpath

  cp "${origin_dir}"/linux_files/wsl-distribution.conf "${TMPDIR}"/dist/etc/wsl-distribution.conf

  mkdir -p "${TMPDIR}"/dist/usr/lib/wsl
  cp "${origin_dir}"/linux_files/oobe.sh "${TMPDIR}"/dist/usr/lib/wsl/oobe.sh
  chmod +x "${TMPDIR}"/dist/usr/lib/wsl/oobe.sh
  cp "${origin_dir}"/linux_files/fedoraremix.ico "${TMPDIR}"/dist/usr/lib/wsl/fedoraremix.ico
  cp "${origin_dir}"/linux_files/terminal-profile.json "${TMPDIR}"/dist/usr/lib/wsl/terminal-profile.json

  #cp "${origin_dir}"/linux_files/wsl2-xwayland.service "${TMPDIR}"/dist/etc/systemd/system/wsl2-xwayland.service
  #cp "${origin_dir}"/linux_files/wsl2-xwayland.socket "${TMPDIR}"/dist/etc/systemd/system/wsl2-xwayland.socket
  #ln -sf ../wsl2-xwayland.socket "${TMPDIR}"/dist/etc/systemd/system/sockets.target.wants/

  #cp "${origin_dir}"/linux_files/wsl-links.conf "${TMPDIR}"/dist/usr/lib/tmpfiles.d/
  #mkdir -p "${TMPDIR}"/dist/usr/share/user-tmpfiles.d
  #cp "${origin_dir}"/linux_files/wsl-links-user.conf "${TMPDIR}"/dist/usr/share/user-tmpfiles.d/

  cp "${origin_dir}"/linux_files/systemctl3.py "${TMPDIR}"/dist/usr/local/bin/wslsystemctl
  chmod +x "${TMPDIR}"/dist/usr/local/bin/wslsystemctl

  cp "${origin_dir}"/linux_files/journalctl3.py "${TMPDIR}"/dist/usr/local/bin/wsljournalctl
  chmod +x "${TMPDIR}"/dist/usr/local/bin/wsljournalctl

  echo "##[section] Masking conflicting services"
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
ln -sf /dev/null /etc/systemd/system/systemd-resolved.service
ln -sf /dev/null /etc/systemd/system/systemd-networkd.service
ln -sf /dev/null /etc/systemd/system/NetworkManager.service
ln -sf /dev/null /etc/systemd/system/NetworkManager-wait-online.service
ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-setup.service
ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-clean.service
ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-clean.timer
ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-setup-dev-early.service
ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-setup-dev.service
ln -sf /dev/null /etc/systemd/system/tmp.mount
EOF

  echo "##[section] Comply with Fedora Remix terms"
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
dnf -y update
dnf -y install generic-release --allowerasing  --releasever="${version_id}"
dnf -y reinstall --skip-unavailable fedora-repos-modular fedora-repos
EOF

  echo "##[section] Overwrite os-release provided by generic-release"
  cp "${origin_dir}"/linux_files/os-release-"${version_id}" "${TMPDIR}"/dist/etc/os-release

  echo "##[section] Install cracklibs-dicts"
  systemd-nspawn --resolv-conf="replace-host" -q -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
dnf -y install --allowerasing --skip-broken cracklib-dicts
EOF

  echo "##[section] Install typical Linux utils"
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
dnf -y install bash-completion vim wget distribution-gpg-keys rsync util-linux-user nano dbus-tools dos2unix

echo 'source /etc/vimrc' > /etc/skel/.vimrc
echo 'set background=dark' >> /etc/skel/.vimrc
echo 'set visualbell' >> /etc/skel/.vimrc
echo 'set noerrorbells' >> /etc/skel/.vimrc

echo '\$include /etc/inputrc' > /etc/skel/.inputrc
echo 'set bell-style none' >> /etc/skel/.inputrc
echo 'set show-all-if-ambiguous on' >> /etc/skel/.inputrc
echo 'set show-all-if-unmodified on' >> /etc/skel/.inputrc
EOF

  echo "##[section] Reinstall crypto-policies and clean up"
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
dnf -y reinstall crypto-policies --exclude=grub\*,dracut*,grubby,kpartx,kmod,os-prober,libkcapi*
dnf -y autoremove
dnf -y clean all
EOF

  echo "##[section] 'Setup Whitewater Foundry repo"
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
curl -s https://packagecloud.io/install/repositories/whitewaterfoundry/fedoraremix/script.rpm.sh | env os=fedora dist=${version_id} bash
dnf update --refresh
EOF

  echo "##[section] 'Install MESA"
  if [ "$arch" = "x86_64" ]; then
    declare -a mesa_version=('24.1.2-7_wsl.fc40' '24.2.5-1_wsl_2.fc41' '25.0.4-2_wsl_3.fc42' '25.3.5-1_wsl.fc43')
    local i=$((${#mesa_version[@]} - 1))
    systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
dnf -y install 'dnf-command(versionlock)'
dnf -y install --allowerasing --nogpgcheck mesa-dri-drivers-"${mesa_version[i]}" mesa-libGL-"${mesa_version[i]}" mesa-va-drivers-"${mesa_version[i]}" mesa-vdpau-drivers-"${mesa_version[i]}" mesa-libEGL-"${mesa_version[i]}" mesa-libgbm-"${mesa_version[i]}" mesa-libxatracker-"${mesa_version[i]}" mesa-vulkan-drivers-"${mesa_version[i]}" glx-utils vdpauinfo libva-utils
dnf versionlock add mesa-dri-drivers mesa-libGL mesa-filesystem mesa-libglapi mesa-va-drivers mesa-vdpau-drivers mesa-libEGL mesa-libgbm mesa-libxatracker mesa-vulkan-drivers

/usr/sbin/groupadd -g 44 wsl-video
EOF
  else
    systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
dnf -y install --allowerasing mesa-dri-drivers mesa-libGL mesa-va-drivers mesa-vdpau-drivers mesa-libEGL mesa-libgbm mesa-libxatracker mesa-vulkan-drivers glx-utils vdpauinfo libva-utils

/usr/sbin/groupadd -g 44 wsl-video
EOF
  fi

  echo "##[section] 'Setup WSLU"
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
curl -s https://packagecloud.io/install/repositories/whitewaterfoundry/wslu/script.rpm.sh | env os=fedora dist=${version_id} bash
dnf -y install wslu
EOF

  echo "##[section] Fix ping"
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
chmod u+s "$(command -v ping)"
#setcap cap_net_raw+ep "$(command -v ping)"
EOF

  echo "##[section] Copy dnf.conf"
  cp "${origin_dir}"/linux_files/dnf.conf "${TMPDIR}"/dist/etc/dnf/dnf.conf

  echo "##[section] Create filesystem tar, excluding unnecessary files"
  cd "${TMPDIR}"/dist
  mkdir -p "${origin_dir}"/"${arch_dir}"
  tar --exclude='boot/*' --exclude=proc --exclude=dev --exclude=sys --exclude='var/cache/dnf/*' --absolute-names --numeric-owner -c * | gzip --best >  "${origin_dir}"/"${arch_dir}"/install.tar.gz

  echo "##[section] Return to origin directory"
  cd "${origin_dir}"

  echo "##[section] Cleanup"
  rm -rf "${TMPDIR}"
}

#######################################
# description
# Arguments:
#  None
#######################################
function usage() {
  echo "./create-targz.sh <BUILD_ARCHITECTURE> <DESTINATION_DIRECTORY> <VERSION>"
  echo "Possible architectures: arm64, x86_64"
}

#######################################
# description
# Globals:
#   HOME
#   TMPDIR
#   arch
#   arch_dir
#   origin_dir
# Arguments:
#   1
#   2
#   3
#######################################
function main() {
  echo "##[section] Set environment"

  set -e

  origin_dir=$(pwd)

  TMPDIR=${2:-$(mktemp -d -p "${HOME}")}

  arch=""
  arch_dir=""

  mkdir -p "${TMPDIR}"

  version_id=${3:-43}
  # shellcheck source=linux_files/os-release-39
  source "linux_files/os-release-${version_id}"

  # Accept argument input for the architecture type
  arch="$1"

  if [ "$arch" = "x86_64" ]; then
    arch="x86_64"
    arch_dir="x64"
    build
  elif [ "$arch" = "arm64" ]; then
    arch="aarch64"
    arch_dir="ARM64"
    build
  else
    usage
  fi

}

main "$@"
