#!/bin/bash
# bashsupport disable=BP5004

echo "##[section] Set environment"
set -e

ORIGINDIR=$(pwd)
TMPDIR=${2:-$(mktemp -d -p "${HOME}")}
ARCH=""
ARCHDIR=""

mkdir -p "${TMPDIR}"

source linux_files/os-release-37

function build() {
  echo "##[section] Install dependencies"
  dnf -y update
  dnf -y install mock qemu-user-static
  if [ "$(uname -i)" != "$ARCH" ]; then
    systemctl restart systemd-binfmt.service
  fi

  echo "##[section] Move to our temporary directory"
  cd "${TMPDIR}"
  mkdir "${TMPDIR}"/dist

  echo "##[section] Make sure /dev is created before later mount"
  mkdir -m 0755 "${TMPDIR}"/dist/dev

  echo "##[section] Use mock to initialise chroot filesystem"
  mock --root="fedora-${VERSION_ID}-${ARCH}" --init --dnf --forcearch="${ARCH}" --rootdir="${TMPDIR}"/dist

  echo "##[section] Bind mount current /dev to new chroot/dev"
  # (fixes '/dev/null: Permission denied' errors)
  mount --bind /dev "${TMPDIR}"/dist/dev

  echo "##[section] Install required packages, exclude unnecessary packages to reduce image size"
  dnf --installroot="${TMPDIR}"/dist --forcearch="${ARCH}" --releasever="${VERSION_ID}" -y install @core libgcc glibc-langpack-en --exclude=grub\*,sssd-kcm,sssd-common,sssd-client,linux-firmware,dracut*,plymouth,parted,e2fsprogs,iprutils,iptables,ppc64-utils,selinux-policy*,policycoreutils,sendmail,kernel*,firewalld,fedora-release,fedora-logos,fedora-release-notes --allowerasing

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

  cat "${ORIGINDIR}"/linux_files/dnf.conf "${TMPDIR}"/dist/etc/dnf/dnf.conf >"${TMPDIR}"/dist/etc/dnf/dnf.temp
  mv "${TMPDIR}"/dist/etc/dnf/dnf.temp "${TMPDIR}"/dist/etc/dnf/dnf.conf

  echo "##[section] Copy over some of our custom files"
  cp "${ORIGINDIR}"/linux_files/wsl.conf "${TMPDIR}"/dist/etc/
  cp "${ORIGINDIR}"/linux_files/local.conf "${TMPDIR}"/dist/etc/fonts/
  cp "${ORIGINDIR}"/linux_files/00-remix.sh "${TMPDIR}"/dist/etc/profile.d/
  cp "${ORIGINDIR}"/linux_files/00-remix.fish "${TMPDIR}"/dist/etc/fish/conf.d/
  chmod -x,+r "${TMPDIR}"/dist/etc/profile.d/00-remix.sh
  chmod -x,+r "${TMPDIR}"/dist/etc/fish/conf.d/00-remix.fish

  cp "${ORIGINDIR}"/linux_files/upgrade.sh "${TMPDIR}"/dist/usr/local/bin/
  chmod +x "${TMPDIR}"/dist/usr/local/bin/upgrade.sh
  ln -s /usr/local/bin/upgrade.sh "${TMPDIR}"/dist/usr/local/bin/update.sh

  cp "${ORIGINDIR}"/linux_files/start-systemd.sudoers "${TMPDIR}"/dist/etc/sudoers.d/start-systemd
  cp "${ORIGINDIR}"/linux_files/start-systemd.sh "${TMPDIR}"/dist/usr/local/bin/start-systemd
  chmod +x "${TMPDIR}"/dist/usr/local/bin/start-systemd

  cp "${ORIGINDIR}"/linux_files/wsl2-xwayland.service "${TMPDIR}"/dist/etc/systemd/system/wsl2-xwayland.service
  cp "${ORIGINDIR}"/linux_files/wsl2-xwayland.socket "${TMPDIR}"/dist/etc/systemd/system/wsl2-xwayland.socket
  ln -sf ../wsl2-xwayland.socket "${TMPDIR}"/dist/etc/systemd/system/sockets.target.wants/

  cp "${ORIGINDIR}"/linux_files/systemctl3.py "${TMPDIR}"/dist/usr/local/bin/wslsystemctl
  chmod +x "${TMPDIR}"/dist/usr/local/bin/wslsystemctl

  echo "##[section] Comply with Fedora Remix terms"
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
dnf -y update
dnf -y install generic-release --allowerasing  --releasever="${VERSION_ID}"
dnf -y reinstall fedora-repos-modular fedora-repos
EOF

  echo "##[section] Overwrite os-release provided by generic-release"
  cp "${ORIGINDIR}"/linux_files/os-release-"${VERSION_ID}" "${TMPDIR}"/dist/etc/os-release

  echo "##[section] Install cracklibs-dicts"
  systemd-nspawn --resolv-conf="replace-host" -q -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
dnf -y install --allowerasing --skip-broken cracklib-dicts
EOF

  echo "##[section] Install typical Linux utils"
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
dnf -y install bash-completion vim wget distribution-gpg-keys rsync util-linux-user nano

echo 'source /etc/vimrc' > /etc/skel/.vimrc
echo 'set background=dark' >> /etc/skel/.vimrc
echo 'set visualbell' >> /etc/skel/.vimrc
echo 'set noerrorbells' >> /etc/skel/.vimrc

echo '\$include /etc/inputrc' > /etc/skel/.inputrc
echo 'set bell-style none' >> /etc/skel/.inputrc
echo 'set show-all-if-ambiguous on' >> /etc/skel/.inputrc
echo 'set show-all-if-unmodified on' >> /etc/skel/.inputrc
EOF

  echo "##[section] Fix ping"
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
chmod u+s "$(command -v ping)"
EOF

  echo "##[section] Reinstall crypto-policies and clean up"
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
dnf -y reinstall crypto-policies --exclude=grub\*,dracut*,grubby,kpartx,kmod,os-prober,libkcapi*
dnf -y autoremove
dnf -y clean all
EOF

  echo "##[section] 'Setup Whitewater Foundry repo"
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
curl -s https://packagecloud.io/install/repositories/whitewaterfoundry/fedoraremix/script.rpm.sh | env os=fedora dist=35 bash
EOF

  echo "##[section] 'Install fix for WSL1 and gpgcheck"
  cp "${ORIGINDIR}"/linux_files/check-dnf.sh "${TMPDIR}"/dist/etc/profile.d
  cp "${ORIGINDIR}"/linux_files/check-dnf.fish "${TMPDIR}"/dist/etc/fish/conf.d/
  cp "${ORIGINDIR}"/linux_files/check-dnf "${TMPDIR}"/dist/usr/bin
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
echo '%wheel   ALL=NOPASSWD: /usr/bin/check-dnf' | sudo EDITOR='tee -a' visudo --quiet --file=/etc/sudoers.d/check-dnf
chmod -w /usr/bin/check-dnf
chmod u+x /usr/bin/check-dnf
chmod -x,+r /etc/fish/conf.d/check-dnf.fish
chmod -x,+r /etc/profile.d/check-dnf.sh
EOF

  echo "##[section] 'Install MESA"
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
dnf -y install 'dnf-command(versionlock)'
dnf -y install --allowerasing --nogpgcheck mesa-dri-drivers-22.3.6-wsl mesa-libGL-22.3.6-wsl mesa-va-drivers-22.3.6-wsl mesa-vdpau-drivers-22.3.6-wsl glx-utils vdpauinfo libva-utils
dnf versionlock add mesa-dri-drivers mesa-libGL mesa-filesystem mesa-libglapi mesa-va-drivers mesa-vdpau-drivers
EOF

  echo "##[section] 'Setup WSLU"
  systemd-nspawn -q --resolv-conf="replace-host" -D "${TMPDIR}"/dist --pipe /bin/bash <<EOF
(
  source /etc/os-release && dnf -y copr enable wslutilities/wslu "\${ID_LIKE}-${VERSION_ID}-${ARCH}"
)
dnf -y install wslu
EOF

  echo "##[section] Copy dnf.conf"
  cp "${ORIGINDIR}"/linux_files/dnf.conf "${TMPDIR}"/dist/etc/dnf/dnf.conf

  echo "##[section] Create filesystem tar, excluding unnecessary files"
  cd "${TMPDIR}"/dist
  mkdir -p "${ORIGINDIR}"/"${ARCHDIR}"
  tar --exclude='boot/*' --exclude=proc --exclude=dev --exclude=sys --exclude='var/cache/dnf/*' --numeric-owner -czf "${ORIGINDIR}"/"${ARCHDIR}"/install.tar.gz ./*

  echo "##[section] Return to origin directory"
  cd "${ORIGINDIR}"

  echo "##[section] Cleanup"
  rm -rf "${TMPDIR}"
}

function usage() {
  echo "./create-targz.sh <BUILD_ARCHITECTURE>"
  echo "Possible architectures: arm64, x86_64"
}

# Accept argument input for architecture type
ARCH="$1"
if [ "$ARCH" = "x86_64" ]; then
  ARCH="x86_64"
  ARCHDIR="x64"
  build
elif [ "$ARCH" = "arm64" ]; then
  ARCH="aarch64"
  ARCHDIR="ARM64"
  build
else
  usage
fi
