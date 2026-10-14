# Remote desktop rewrite of `install-desktop.sh` — status and handoff

This document is for whoever continues this work (human or AI). It records what was changed, why, what was
verified, and what is still open.

## Goal

Rewrite `linux_files/install-desktop.sh` (installed as `/usr/local/bin/install-desktop.sh` by
`create-targz.sh`) so it:

- uses **gnome-remote-desktop** (GNOME) or **KRdp** (KDE Plasma) instead of xrdp;
- offers only **GNOME** and **KDE** (Xfce and LXDE were removed);
- leaves a working desktop that can be reached from Windows with **Remote Desktop Connection (mstsc)**.

Target: Fedora Remix for WSL 44 (GNOME 50, Plasma 6.6/6.7, systemd 259), WSL2 only.

## Design

WSL has no physical display, seat or DRM/KMS output, so neither desktop can use a display manager. Both
desktops run a **headless session** started by a system unit, and the RDP server shares that session.

### GNOME

| Piece | Source | Notes |
|---|---|---|
| `gnome-headless-session@<user>.service` | `gdm` package | Runs `/usr/libexec/gdm-headless-login-session --user=<user>`. It opens a PAM session (`gdm-autologin`) with `XDG_SESSION_TYPE=wayland` and no seat, so mutter runs headless. It needs `X-GDM-CanRunHeadless=true` in `/usr/share/wayland-sessions/gnome.desktop`, which comes from `gnome-session-wayland-session`. |
| `gnome-remote-desktop-headless.service` (user unit) | `gnome-remote-desktop` | `WantedBy=gnome-session.target`. Enabled with a manual symlink in `~/.config/systemd/user/gnome-session.target.wants/`. |
| Configuration | `grdctl --headless rdp ...` | Sets port, disables port negotiation, sets the TLS cert/key (self-signed, made with openssl), disables view-only, and sets the credentials. Credentials fall back to a GKeyFile at `~/.local/share/gnome-remote-desktop/credentials.ini` because WSL has no TPM. |
| RDP credentials | asked in the script | A separate RDP username/password, not the Linux password. |

The template unit has no `[Install]` section, so the script creates the symlink
`/etc/systemd/system/multi-user.target.wants/gnome-headless-session@<user>.service` itself. It also adds the
drop-in `/etc/systemd/system/gnome-headless-session@.service.d/wsl.conf`, which orders the unit after
`systemd-user-sessions`, `accounts-daemon` and `wsl-x11-unix`. Fedora's `gdm-headless-login-session` copies
the unit's environment into the session, so the drop-in also sets `GNOME_REMOTE_DESKTOP_SESSION=1` (the
equivalent of xrdp's `XRDP_SESSION`), `XDG_CURRENT_DESKTOP=GNOME`, `DESKTOP_SESSION=gnome` and `GSK_RENDERER=gl`. The last one makes GTK 4 apps use the OpenGL renderer, because the Vulkan renderer
fails with an out-of-memory error on Mesa's D3D12 Vulkan driver (dzn). **Verified.** GTK still prints
`MESA-EGL` and dzn warnings at startup; they are harmless. Stock Fedora 44 Mesa already includes d3d12 and
dzn, so the WSL Mesa build isn't needed for this. It does not set
`PAM_RHOST`, so `loginctl` reports `Remote=no` and cannot be used for detection. The KDE unit sets
`KRDP_SESSION=1` for the same purpose.

### KDE

KRdp cannot start a session; it only shares a running Plasma session. The script creates:

| File | Purpose |
|---|---|
| `/etc/systemd/system/plasma-headless-session@.service` | `User=%i`, `PAMName=plasma-headless`, sets `XDG_SESSION_TYPE=wayland` and runs `startplasma-wayland`. `DBUS_SESSION_BUS_ADDRESS` is forced to `$XDG_RUNTIME_DIR/bus` (escaped as `$$` for systemd). Enabled with `systemctl enable plasma-headless-session@<user>`. |
| `/etc/pam.d/plasma-headless` | Session-only PAM stack (`auth pam_deny`; `session include system-auth`/`postlogin`). systemd's `PAMName=` never authenticates, it only opens the session. |
| `~/.config/systemd/user/plasma-kwin_wayland.service.d/headless.conf` | Overrides ExecStart with `kwin_wayland_wrapper --xwayland --virtual --no-lockscreen --width 1920 --height 1080`. In Plasma 6, KWin is the user unit `plasma-kwin_wayland.service`, and the wrapper forwards extra arguments to `kwin_wayland`. |
| `~/.config/systemd/user/app-org.kde.krdpserver.service.d/headless.conf` | `krdpserver --plasma --port <port> --certificate ... --certificate-key ...`. `--plasma` uses KWin's screencast/fake-input protocols instead of xdg-desktop-portal, which would ask for interactive approval. |
| symlink `~/.config/systemd/user/plasma-workspace.target.wants/app-org.kde.krdpserver.service` | Enables KRdp. It is disabled by preset (`00-krdp.preset`). |
| `~/.config/krdpserverrc` `[General]` | `ListenPort`, `SystemUserEnabled=true`, `Certificate`, `CertificateKey`, `AutogenerateCertificates=false`, `Autostart=true` (written with `kwriteconfig6`). |
| `~/.config/kscreenlockerrc` | `Autolock=false`, `LockOnResume=false`. |

Login uses the **Linux username and password**. With `SystemUserEnabled`, KRdp authenticates through PAM
(service `login`, **verified**). **This only works with TLS security, not NLA.** See the open item in Status. KRdp only streams
H.264, so the script installs Cisco `openh264` (`--allowerasing --enablerepo=fedora-cisco-openh264`) in place
of the `noopenh264` stub.

### Shared pieces

- **`/etc/systemd/system/wsl-x11-unix.service`** (oneshot, enabled): WSLg mounts `/tmp/.X11-unix` as a
  read-only tmpfs, so mutter/KWin cannot create Xwayland sockets. The unit unmounts it, recreates it with mode
  1777, and links `X0 -> /mnt/wslg/.X11-unix/X0` so WSLg X apps keep working. **Verified**: Xwayland then
  creates `X1`/`X2`.
- **`systemd-pam`** is installed. **The Fedora Remix rootfs does not ship it**, so without it there is no
  `pam_systemd`, no logind sessions and no `user@.service` ("Trying to run as user instance, but
  $XDG_RUNTIME_DIR is not set"). This was the first blocker found. **Consider adding `systemd-pam` to the
  rootfs build itself.**
- `gdm`, `sddm`, `xrdp` and `xrdp-sesman` are disabled if present. Old xrdp setups would otherwise hold the port.
- avahi + nss-mdns (`<hostname>.local`), locale (`localectl`, or `/etc/locale.conf` when systemd isn't
  running), `/etc/wsl.conf` `systemd=true` and hostname, and the existing service masking were all kept.
- `run_with_session_bus`: uses `/run/user/$UID/bus` if it exists. Otherwise it runs `dbus-run-session` with a
  writable `XDG_RUNTIME_DIR` (a temp dir if needed). **Reason**: in the first test, dconf could not create
  `/run/user/1000/dconf`, and `grdctl`/`gsettings` **silently dropped the settings while exiting 0**. The script
  now checks `grdctl --headless status` for the port afterwards.
- The script refuses to run as root, and `$USER` was replaced by `CURRENT_USER=$(id -un)` because of `set -u`.
- Default RDP port is still **3396**, so it doesn't clash with Windows' own RDP on 3389. The xrdp "session
  manager listen port" prompt was removed.

## Fixes found during testing

1. **`systemd-pam` missing**: see above.
2. **dconf settings silently lost**: see `run_with_session_bus` above.
3. **gnome-remote-desktop-daemon segfaults** right after initialising Mesa's D3D12 Vulkan driver (`dzn`,
   "not a conformant Vulkan implementation"). Fix: the user drop-in
   `~/.config/systemd/user/gnome-remote-desktop-headless.service.d/wsl.conf` with
   `Environment=VK_LOADER_DRIVERS_DISABLE=*dzn*`. After that, the log shows "RDP server started" on 3396.
   KRdp and KWin did not crash in the test, so they don't need it.
4. GNOME Initial Setup and the welcome tour are skipped (`~/.config/gnome-initial-setup-done`,
   `org.gnome.shell welcome-dialog-last-shown-version 999`). Screen lock and idle are disabled with gsettings.

## Test environment and how to test

- Dev distro: `WhitewaterFoundryWSL` (Pengwin/Debian; holds the repo). Test distro: **`fedoraremix44`**
  (Fedora Remix 44, systemd enabled, user `user`, **password `user`**).
- Transfer files through `/mnt/wsl/desktop-test/` (shared between distros). It is a **tmpfs, wiped when WSL
  shuts down**; copies of all test scripts (`gnome.sh`, `kde.sh`, `t1.sh`-`t8.sh`) and the GNOME screenshot are in
  `/home/user/desktop-test-backup/` in `WhitewaterFoundryWSL`. Run commands with
  `wsl.exe -d fedoraremix44 -u user|root -- bash /mnt/wsl/desktop-test/<script>.sh`. Put commands in files,
  because inline `wsl.exe ... bash -c '...'` quoting mangles `$vars`.
- whiptail can't be driven non-interactively, so tests source the script's functions:
  `sed '$d' install-desktop.sh > /mnt/wsl/desktop-test/lib.sh` (removes the final `main "$@"`). Then
  `gnome.sh` / `kde.sh` call the functions in `main`'s order with test values.
- **Temporary test-only change**: `/etc/sudoers.d/zz-desktop-test` (`user ALL=(ALL) NOPASSWD: ALL`) was
  added in `fedoraremix44`. **Remove it when testing is finished.**
- Pre-existing quirks of that distro, unrelated to the script: networking looks mirrored (sshd conflicts with
  Windows on port 22; something already listens on `*:3389`), systemd boots slowly ("/sbin/init failed to
  start within 10000ms"), and auditd fails.
- End-to-end RDP check, run inside the distro: `dnf install freerdp xorg-x11-server-Xvfb xwd ImageMagick`,
  start `Xvfb :55`, run `DISPLAY=:55 xfreerdp /v:localhost:3396 /u:... /p:... /cert:ignore /size:1280x800`,
  then take a screenshot with `xwd -root | magick xwd:- out.png` (see `t7.sh`). For authentication only, use
  `xfreerdp ... /auth-only`; "exit status 1" means success.

## Status

| Item | Status |
|---|---|
| Script syntax / shellcheck | Clean |
| GNOME install path | **Verified end to end** in fedoraremix44: install ran, the session starts at boot, grd listens on 3396, a wrong password is rejected, and the right one shows the full GNOME desktop over RDP (screenshot `/mnt/wsl/desktop-test/gnome-rdp.png`). |
| GNOME fixes added after that run (dconf temp runtime dir, status check, dzn drop-in, welcome tour) | Written into the script; the dzn drop-in was verified by hand. **Re-run the GNOME path once on a clean distro** to confirm. |
| KDE install path | **Verified.** The install ran in fedoraremix44, after disabling the GNOME headless session there. Log: `kde.log` in the backup folder. |
| KDE runtime | **Verified with TLS security.** At boot `plasma-headless-session@user` → `plasma-kwin_wayland` (virtual backend) → plasmashell → `krdpserver` listening on 3396. Over `xfreerdp /sec:tls /u:user /p:user`, the PAM login works (`login` service) and H.264 streams via openh264; screenshot `kde-rdp-final.png`. No dzn crash in KWin or KRdp, but KWin falls back to llvmpipe. Plasma's own Discover/PackageKit shows a polkit prompt "modify a system repository" on first login; that is not from the script. |
| **KDE + NLA (OPEN, blocks default mstsc)** | KRdp offers NLA, and NLA logins fail: "ntlm_fetch_ntlm_v2_hash: Could not find user in SAM database". This happens with `SystemUserEnabled` (expected, PAM can't verify NTLM) **and also with `krdpserver --username/--password`** (tested with simple passwords and several `/d:` domains). TLS with `--username/--password` gave a black screen and krdpserver restarted. So the script uses PAM mode, and the summary tells KDE users to save the connection as an `.rdp` file and add `enablecredsspsupport:i:0`. **Not yet tested with real mstsc**, and mstsc may then not send the password at all. Ideas to try: (1) users in `krdpserverrc` `Users=` with the password in the keychain (QtKeychain service "KRDP", backed by ksecretd/kwallet; needs an unlocked wallet in the headless session); (2) a newer KRdp, or check upstream for NLA-off or PAM-over-NLA options; (3) xrdp-style fallback for KDE. |
| Real Windows `mstsc` test | Not done yet. Connect to `localhost:3396`. |
| Test distro state | fedoraremix44 now has **both** GNOME and KDE installed. The GNOME headless session was disabled for the KDE test (removed the `multi-user.target.wants/gnome-headless-session@user.service` and `~/.config/systemd/user/gnome-session.target.wants/...` symlinks), so the KDE session is the one that starts. Re-test both on clean distros. |
| Commit | Nothing committed. The branch is `development`; only `linux_files/install-desktop.sh` and this doc changed. |

## Known limitations

- WSL stops the distro when no WSL terminal is open, so a terminal must stay open while using RDP. This is
  shown in the final summary.
- The GNOME RDP password is passed to `grdctl` on the command line (briefly visible in `ps`) and stored as
  plain text in `credentials.ini` (mode 600).
- The KDE resolution is fixed at 1920x1080 (`KDE_HEADLESS_WIDTH`/`HEIGHT`). GNOME uses the client's size.
- WSLg's `/run/user/1000/wayland-0` already exists, so mutter uses `wayland-1`. That is expected.
