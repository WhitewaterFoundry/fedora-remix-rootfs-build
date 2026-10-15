# Copilot Instructions

This repo builds the **Fedora Remix for WSL** root filesystem (`install.tar.gz`) for x86_64 and ARM64. It is almost entirely bash; there is no unit-test suite.

## Build / lint / validate

```bash
# Lint (CI runs ShellCheck at severity "error" on push/PR to master)
bash -n create-targz.sh linux_files/upgrade.sh
shellcheck -S warning create-targz.sh linux_files/upgrade.sh

# Build (Fedora host, root, needs mock + qemu-user-static). Args: <x86_64|arm64> [tmpdir] [fedora_version]
sudo bash create-targz.sh x86_64 "$PWD/rootfs" 44
sudo bash create-targz.sh arm64  "$PWD/rootfs" 44
```

There is no single-test command. Validate by importing the resulting `x64/install.tar.gz` (or `ARM64/`) into WSL and checking `/etc/os-release`, `glxinfo -B` (D3D12 on x86_64), and that `upgrade.sh` runs on WSL1 and WSL2.

## Architecture

- `create-targz.sh` is the core build. It uses `mock --init --forcearch` and `dnf --installroot` to bootstrap a minimal Fedora chroot, copies files from `linux_files/` into specific rootfs paths (e.g. `00-remix.sh` → `/etc/profile.d/`, `systemctl3.py` → `/usr/local/bin/wslsystemctl`, sudoers files → `/etc/sudoers.d/`), installs packages from Whitewater Foundry packagecloud repos (`fedoraremix` for the WSL Mesa build, `wslu`), then tars the result. The copy destinations are hardcoded in the script — adding a file to `linux_files/` does nothing until `create-targz.sh` copies it.
- `linux_files/upgrade.sh` ships inside the image (`/usr/local/bin/upgrade.sh`) and upgrades existing installs; it downloads `os-release-${VERSION_ID}` from GitHub `master` at runtime.
- `azure-pipelines.yml` + `debootstrap_architecture_template.yml` run the build per architecture on Fedora agents (triggered on `master`); the template invokes `create-targz.sh` with a hardcoded Fedora version.
- `update-targz*.sh`, `Vagrantfile`, `copy_images.sh`, `restore-backups.sh` are auxiliary tooling for updating/copying an existing tarball in a Vagrant VM.

## Conventions

- Fedora version bumps touch several places that must stay in sync: new `linux_files/os-release-N`, `version_id=${3:-N}` default in `create-targz.sh`, the version in `debootstrap_architecture_template.yml`, and `mesa_version`/`target_version` in `linux_files/upgrade.sh`. **Follow `docs/upgrading-fedora-version.md`** for the full procedure.
- `mesa_version` in `create-targz.sh`: the build installs the **last** array entry, so append new versions. In `upgrade.sh`, `mesa_version` and `target_version` are index-aligned and must have equal length.
- Mesa uses the custom WSL (d3d12) build on x86_64 only; ARM64 uses stock Fedora Mesa.
- Work flows `development` → `master`; merging to `master` triggers the release build, and `upgrade.sh`/`os-release-N` must exist on `master` before users run upgrades.
- Scripts support both WSL1 and WSL2; workarounds in `upgrade.sh` are version-gated (e.g. `ensure_wsl1_pixbuf_compat` for `>= 43`) — extend rather than remove them.
- Shell scripts use `# shellcheck` directives and the `##[section]` log-prefix style for Azure Pipelines output.
