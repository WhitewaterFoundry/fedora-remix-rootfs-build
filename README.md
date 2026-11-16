# fedora-remix-rootfs-build

## DNF4 autoremove protected package error

After a release upgrade, `dnf4 autoremove` can fail because it tries to remove
the protected `grub2-tools-minimal` package as an unused dependency. If this
happens, mark the installed package as user-installed and retry cleanup:

```bash
sudo dnf4 mark install grub2-tools-minimal &&
  sudo dnf4 -y autoremove
```

This keeps the package and its protection in place. Run these commands after
the system upgrade, before or instead of retrying the autoremove step.

## Fedora 43 to 44 repository CA-bundle workaround

The [Fedora Remix for WSL 44.0.0 upgrade instructions](https://www.whitewaterfoundry.com/blog/2026/11/2/fedora-remix-for-wsl-4400-released)
refer to `whitewaterfoundry_wslu.repo`, which may not exist on your system.
In place of the `sed` command in those instructions, run the following to
update the old CA-bundle path in each Whitewater Foundry repository file that
exists:

```bash
for repo in /etc/yum.repos.d/whitewaterfoundry_{fedoraremix,wslu}.repo; do
  if [[ -f "$repo" ]] && grep -qxF 'sslcacert=/etc/pki/tls/certs/ca-bundle.crt' "$repo"; then
    if [[ ! -e "$repo.bak" && ! -L "$repo.bak" ]]; then
      sudo cp -p -- "$repo" "$repo.bak" || continue
    fi
    sudo sed -i \
      's|^sslcacert=/etc/pki/tls/certs/ca-bundle.crt$|sslcacert=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem|' \
      "$repo"
  fi
done
```

Changed files are backed up with a `.bak` suffix. Missing files are skipped;
there is no need to create the WSLU repository just to run this workaround.
