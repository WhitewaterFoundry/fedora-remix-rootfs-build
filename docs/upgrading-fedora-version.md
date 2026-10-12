# Upgrading the rootfs to a new Fedora release

This document describes how to bump the Fedora Remix for WSL rootfs build to a
new Fedora release. It was written while moving from Fedora 43 to Fedora 44 and
follows the same pattern as previous upgrades (see commits `c6493fc` for 42 and
`d363f13` for 43).

In the examples below, `N` is the new Fedora version (e.g. `44`) and `N-1` is
the previous one (e.g. `43`).

## 1. Prerequisites outside this repository

The build and `upgrade.sh` install packages from the Whitewater Foundry
packagecloud repositories using `dist=N`. Before the build can succeed these
must be published for `fedora/N`:

| Repository | Package(s) | Notes |
|------------|------------|-------|
| [`whitewaterfoundry/fedoraremix`](https://packagecloud.io/whitewaterfoundry/fedoraremix) | WSL Mesa build (`mesa-*-<ver>_wsl.fcN`, x86_64) | Mesa rebuilt with the d3d12 Gallium driver for WSLg. Must match the version listed in `create-targz.sh` and `upgrade.sh`. |
| `whitewaterfoundry/fedoraremix` | `gdk-pixbuf2-2.42.*` | Used by the WSL1 workaround in `upgrade.sh` (`ensure_wsl1_pixbuf_compat`). For `fedora/43`, the `fc42` build is published. |
| [`whitewaterfoundry/wslu`](https://packagecloud.io/whitewaterfoundry/wslu) | `wslu` (noarch) | The same noarch RPM can be pushed to the new `fedora/N` distribution. |

You can check whether a repository has packages for a release with:

```bash
curl -sL https://packagecloud.io/whitewaterfoundry/fedoraremix/fedora/44/x86_64/repodata/repomd.xml
```

If it lists `repodata/primary.xml.gz` with no hash prefix, the distribution
exists but is empty.

To choose the Mesa version, check what Fedora ships in
`https://dl.fedoraproject.org/pub/fedora/linux/updates/N/Everything/x86_64/Packages/m/`
and build the WSL variant from that source RPM.

## 2. Changes in this repository

### 2.1 Add `linux_files/os-release-N`

Copy `linux_files/os-release-(N-1)` and replace the version everywhere:

- `VERSION="N"`
- `VERSION_ID=N`
- `PLATFORM_ID="platform:fN"`
- `CPE_NAME="cpe:/o:fedoraproject:fedora:N"`
- `FEDORA_REMIX_VERSION=N.0.0`

`create-targz.sh` copies this file into the image as `/etc/os-release`, and
`upgrade.sh` downloads `os-release-${VERSION_ID}` from GitHub on existing
installs, so the file must exist on `master` before users run `upgrade.sh`.

### 2.2 `create-targz.sh`

- Change the default version: `version_id=${3:-N}`.
- Append the new WSL Mesa version to the end of the `mesa_version` array
  (x86_64 branch). The build always installs the **last** entry, so the order
  matters.

ARM64 uses the stock Fedora Mesa packages and needs no change.

### 2.3 `debootstrap_architecture_template.yml`

Change the version passed to the build script:

```yaml
- script: sudo bash create-targz.sh $(ARCH) "$PWD/rootfs" N
```

### 2.4 `linux_files/upgrade.sh`

- Append the new Mesa version to `mesa_version` and `N` to `target_version`.
  The two arrays are index-aligned and must stay the same length.
- Review the version-specific workarounds and extend them if the new release
  is still affected. For Fedora 44 the WSL1 gdk-pixbuf/glycin workaround
  (`ensure_wsl1_pixbuf_compat`) was changed from `== 43` to `>= 43` because
  Fedora 44 still ships gdk-pixbuf2 2.44 with the glycin loaders, which need
  `memfd`, and WSL1 does not provide it.

### 2.5 Other files to review

- `linux_files/wsl.conf`, `00-remix.sh`, `00-remix.fish`: usually unchanged,
  but check the Fedora release notes for changes to systemd, dnf, or the
  default shell environment.
- The `dnf` and `mock` versions on the Fedora build agents: `mock` needs a
  `fedora-N-<arch>` config, so the agent's `mock-core-configs` package must be
  new enough.

## 3. Validate

```bash
bash -n create-targz.sh linux_files/upgrade.sh
shellcheck -S warning create-targz.sh linux_files/upgrade.sh

# Local build on a Fedora host (requires root, mock, qemu-user-static)
sudo bash create-targz.sh x86_64 "$PWD/rootfs" 44
sudo bash create-targz.sh arm64  "$PWD/rootfs" 44
```

Then import the generated `x64/install.tar.gz` into WSL and check:

- `cat /etc/os-release` shows the new version.
- `glxinfo -B` reports the `D3D12` renderer (x86_64, WSLg).
- `wslsys -v` reports wslu v4.
- `upgrade.sh` runs cleanly on WSL2 and WSL1.

## 4. Release

Merge `development` into `master`. The Azure pipeline (`azure-pipelines.yml`)
builds the x86_64 and ARM64 rootfs artifacts on the Fedora agents.
