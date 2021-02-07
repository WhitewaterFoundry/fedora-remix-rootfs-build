#! /bin/bash

set -x

cp build/install_amd64_rootfs.tar.gz ../Pengwin/x64/install.tar.gz
cp build/install_arm64_rootfs.tar.gz ../Pengwin/ARM64/install.tar.gz
