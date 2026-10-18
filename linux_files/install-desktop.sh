#!/bin/bash
#
# install-desktop.sh - Fedora Remix Desktop Setup Script
#
# This script provides an interactive setup for configuring a remote desktop
# in Fedora Remix WSL distribution. It installs GNOME or KDE Plasma and runs a
# headless (no physical display) session that can be reached from Windows with
# the Remote Desktop Connection client (mstsc):
#
#   GNOME - headless GNOME session (gnome-headless-session@.service from gdm)
#           shared by gnome-remote-desktop in headless mode.
#   KDE   - headless Plasma Wayland session (KWin virtual backend) shared by
#           KRdp, authenticating with the Linux user account through PAM.
#
# Globals:
#   PENGWIN_SETUP_TITLE - Title for whiptail dialogs
#   NEWT_COLORS - Color scheme for newt/whiptail dialogs
# Arguments:
#   None
# Returns:
#   0 on success, 1 on error or user cancellation

set -euo pipefail

# Constants
readonly PENGWIN_SETUP_TITLE="Pengwin Setup"
readonly DEFAULT_HOSTNAME="fedoraremix"
readonly DEFAULT_RDP_PORT="3396"
readonly DEFAULT_LOCALE="en_US.UTF-8"
readonly KDE_HEADLESS_WIDTH="1920"
readonly KDE_HEADLESS_HEIGHT="1080"
readonly SYSTEMD_SYSTEM_DIR="/etc/systemd/system"
readonly X11_UNIX_FIX_SERVICE="wsl-x11-unix.service"
readonly PLASMA_HEADLESS_PAM="plasma-headless"
CURRENT_USER="$(id -un)"
readonly CURRENT_USER

# Color scheme for whiptail dialogs
export NEWT_COLORS='
    root=lightgray,black
    roottext=lightgray,black
    shadow=black,gray
    title=magenta,lightgray
    checkbox=lightgray,blue
    actcheckbox=lightgray,magenta
    emptyscale=lightgray,blue
    fullscale=lightgray,magenta
    button=lightgray,magenta
    actbutton=magenta,lightgray
    compactbutton=magenta,lightgray
    listbox=lightgray,blue
    actlistbox=lightgray,magenta
    sellistbox=lightgray,magenta
    actsellistbox=lightgray,magenta
'

# Get the primary IP address of the WSL instance
function get_wsl_ip_address() {
  local ip_address=""

  # Try to get IP from hostname -I first (most reliable)
  if command -v hostname >/dev/null 2>&1; then
    ip_address=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
  fi

  # Fallback to ip route if hostname -I failed
  if [[ -z "${ip_address}" ]]; then
    ip_address=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1 || true)
  fi

  # Final fallback to parsing ip addr
  if [[ -z "${ip_address}" ]]; then
    ip_address=$(ip addr show 2>/dev/null | grep -E 'inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -1 || true)
  fi

  # Default if all methods fail
  if [[ -z "${ip_address}" ]]; then
    ip_address="<Unable to detect IP>"
  fi

  echo "${ip_address}"
}

# Display final configuration summary
function show_configuration_summary() {
  local hostname="${1}"
  local rdp_port="${2}"
  local desktop_choice="${3}"
  local rdp_username="${4}"
  local ip_address="${5}"

  local credentials_hint
  if [[ ${desktop_choice} == "GNOME" ]]; then
    credentials_hint="Log in with the RDP username and password you entered in this setup."
  else
    credentials_hint="Log in with your Linux username and password. KRdp does not support NLA logins with\n"
    credentials_hint+="Linux accounts: in mstsc save the connection as an .rdp file and add the line\n"
    credentials_hint+="  enablecredsspsupport:i:0"
  fi

  local summary_text=""
  summary_text+="Setup completed successfully!\n\n"
  summary_text+="CONFIGURATION SUMMARY:\n"
  summary_text+="=====================\n\n"
  summary_text+="Hostname: ${hostname}\n"
  summary_text+="Desktop Environment: ${desktop_choice}\n"
  summary_text+="RDP Port: ${rdp_port}\n"
  summary_text+="RDP Username: ${rdp_username}\n"
  summary_text+="WSL IP Address: ${ip_address}\n\n"
  summary_text+="CONNECTION INFORMATION:\n"
  summary_text+="======================\n\n"
  summary_text+="Open \"Remote Desktop Connection\" (mstsc.exe) on Windows and connect to:\n"
  summary_text+="  localhost:${rdp_port}\n\n"
  summary_text+="Alternatives:\n"
  summary_text+="  ${hostname}.local:${rdp_port}  or  ${ip_address}:${rdp_port}\n\n"
  summary_text+="${credentials_hint}\n"
  summary_text+="Accept the self-signed certificate warning on the first connection.\n\n"
  summary_text+="WSL stops the distribution when no terminal is open, so keep a\n"
  summary_text+="${WSL_DISTRO_NAME:-Fedora Remix} terminal running while using the remote desktop.\n\n"
  summary_text+="The WSL distribution will now restart to apply changes."

  whiptail --backtitle "${PENGWIN_SETUP_TITLE}" \
    --title "Setup Complete - Configuration Summary" \
    --scrolltext \
    --msgbox "${summary_text}" 30 90
}

# Run update script
function run_update_script() {
  if command -v update.sh >/dev/null 2>&1; then
    echo "Running update script..."
    if ! update.sh; then
      echo "Warning: Update script failed, continuing..." >&2
    fi
  else
    echo "Update script not found, skipping..."
  fi
}

# Install required packages for the user interface
function install_ui_dependencies() {
  if ! sudo dnf -y install newt ncurses dialog; then
    echo "Error: Failed to install UI dependencies" >&2
    return 1
  fi
}

# Get hostname from user input
function get_hostname_input() {
  local hostname
  if ! hostname=$(whiptail --backtitle "${PENGWIN_SETUP_TITLE}" \
    --title "Enter the desired hostname that will identify this distribution instead of IP address" \
    --inputbox "hostname: " 8 100 "${DEFAULT_HOSTNAME}" 3>&1 1>&2 2>&3); then
    echo "Error: Hostname input cancelled" >&2
    return 1
  fi

  if [[ -z "${hostname}" ]]; then
    echo "Error: Hostname cannot be empty" >&2
    return 1
  fi

  # Validate hostname: alphanumeric, hyphens, and periods; must not start or end with a hyphen; 1-253 chars
  if [[ ${#hostname} -gt 253 ]]; then
    echo "Error: Hostname must not exceed 253 characters" >&2
    return 1
  fi

  if ! [[ "${hostname}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    echo "Error: Invalid hostname. Use only alphanumeric characters, hyphens, and periods." >&2
    return 1
  fi

  echo "${hostname}"
}

# Get RDP port from user input
function get_rdp_port_input() {
  local port
  if ! port=$(whiptail --backtitle "${PENGWIN_SETUP_TITLE}" \
    --title "Enter the desired RDP Port" \
    --inputbox "RDP Port (avoid 3389 if Windows Remote Desktop is enabled): " 8 70 "${DEFAULT_RDP_PORT}" 3>&1 1>&2 2>&3); then
    echo "Error: RDP port input cancelled" >&2
    return 1
  fi

  if [[ -z "${port}" ]]; then
    echo "Error: RDP port cannot be empty" >&2
    return 1
  fi

  # Validate that the port is numeric
  if ! [[ "${port}" =~ ^[0-9]+$ ]]; then
    echo "Error: RDP port must be a numeric value" >&2
    return 1
  fi

  # Validate that the port is within the valid range 1-65535
  if (( 10#${port} < 1 || 10#${port} > 65535 )); then
    echo "Error: RDP port must be between 1 and 65535" >&2
    return 1
  fi
  echo "$(( 10#${port} ))"
}

# Get desktop environment selection from user
function get_desktop_choice() {
  local desktop_choice
  if ! desktop_choice=$(whiptail --backtitle "${PENGWIN_SETUP_TITLE}" \
    --title "Desktop Selection" --radiolist --separate-output \
    "Choose your desired Desktop Environment\n[SPACE to select, ENTER to confirm]:" \
    12 50 1 \
    "GNOME" "GNOME Desktop Environment   " on 3>&1 1>&2 2>&3); then
    echo "Error: Desktop selection cancelled" >&2
    return 1
  fi

  if [[ -z "${desktop_choice}" ]]; then
    echo "Error: No desktop environment selected" >&2
    return 1
  fi

  echo "${desktop_choice}"
}

# Get the RDP username from user input (GNOME Remote Desktop has its own credentials)
function get_rdp_username_input() {
  local username
  if ! username=$(whiptail --backtitle "${PENGWIN_SETUP_TITLE}" \
    --title "Enter the username used to log in over RDP" \
    --inputbox "RDP Username: " 8 70 "${CURRENT_USER}" 3>&1 1>&2 2>&3); then
    echo "Error: RDP username input cancelled" >&2
    return 1
  fi

  if [[ -z "${username}" ]]; then
    echo "Error: RDP username cannot be empty" >&2
    return 1
  fi

  if [[ "${username}" =~ [[:space:]] ]]; then
    echo "Error: RDP username must not contain spaces" >&2
    return 1
  fi

  echo "${username}"
}

# Get the RDP password from user input, asking twice for confirmation
function get_rdp_password_input() {
  local password password_confirmation
  if ! password=$(whiptail --backtitle "${PENGWIN_SETUP_TITLE}" \
    --title "Enter the password used to log in over RDP" \
    --passwordbox "RDP Password: " 8 70 3>&1 1>&2 2>&3); then
    echo "Error: RDP password input cancelled" >&2
    return 1
  fi

  if [[ -z "${password}" ]]; then
    echo "Error: RDP password cannot be empty" >&2
    return 1
  fi

  if ! password_confirmation=$(whiptail --backtitle "${PENGWIN_SETUP_TITLE}" \
    --title "Confirm the RDP password" \
    --passwordbox "RDP Password (again): " 8 70 3>&1 1>&2 2>&3); then
    echo "Error: RDP password input cancelled" >&2
    return 1
  fi

  if [[ "${password}" != "${password_confirmation}" ]]; then
    echo "Error: RDP passwords do not match" >&2
    return 1
  fi

  echo "${password}"
}

# Install required tools
function install_required_tools() {
  if ! sudo dnf -y install crudini openssl avahi nss-mdns glibc-langpack-en systemd-pam /usr/bin/dbus-run-session; then
    echo "Error: Failed to install required tools" >&2
    return 1
  fi
}

# Configure WSL settings
function configure_wsl_settings() {
  local hostname="${1}"

  if [[ -z "${hostname}" ]]; then
    echo "Error: hostname parameter is required" >&2
    return 1
  fi

  # Set systemd=true in [boot] section
  if ! sudo crudini --set /etc/wsl.conf boot systemd true; then
    echo "Error: Failed to configure systemd in /etc/wsl.conf" >&2
    return 1
  fi

  # Set hostname in [network] section
  if ! sudo crudini --set /etc/wsl.conf network hostname "${hostname}"; then
    echo "Error: Failed to configure hostname in /etc/wsl.conf" >&2
    return 1
  fi
}

# Install desktop environment and its remote desktop server
function install_desktop_environment() {
  local desktop_choice="${1}"

  if [[ -z "${desktop_choice}" ]]; then
    echo "Error: desktop_choice parameter is required" >&2
    return 1
  fi

  echo "Installing ${desktop_choice} desktop environment..."

  # Desktop environment group mappings
  declare -A desktop_group
  desktop_group["GNOME"]="gnome-desktop"
  desktop_group["KDE"]="kde-desktop"

  # Remote desktop packages, gdm provides gnome-headless-session@.service
  declare -A desktop_rdp_packages
  desktop_rdp_packages["GNOME"]="gnome-remote-desktop gdm gnome-session-wayland-session accountsservice"
  desktop_rdp_packages["KDE"]="krdp kwin plasma-workspace kf6-kconfig"

  local group_to_install="${desktop_group[${desktop_choice}]:-}"

  if [[ -z "${group_to_install}" ]]; then
    echo "Error: Unknown desktop environment: ${desktop_choice}" >&2
    return 1
  fi

  if ! sudo dnf -y group install "${group_to_install}"; then
    echo "Error: Failed to install ${desktop_choice} desktop environment" >&2
    return 1
  fi

  local -a rdp_packages
  read -r -a rdp_packages <<<"${desktop_rdp_packages[${desktop_choice}]}"
  if ! sudo dnf -y install "${rdp_packages[@]}"; then
    echo "Error: Failed to install ${desktop_choice} remote desktop packages" >&2
    return 1
  fi

  # KRdp only streams H.264, which needs the real Cisco OpenH264 library instead of the noopenh264 stub
  if [[ ${desktop_choice} == "KDE" ]]; then
    if ! sudo dnf -y install --allowerasing --enablerepo=fedora-cisco-openh264 openh264 &&
      ! sudo dnf -y install --allowerasing openh264; then
      echo "Warning: Failed to install openh264, KRdp may be unable to encode the video stream" >&2
    fi
  fi
}

# Configure system locale
function configure_system_locale() {
  local systemd_pid="${1:-}"

  if [[ -n "${systemd_pid}" ]]; then
    if ! sudo localectl set-locale "LANG=${DEFAULT_LOCALE}"; then
      echo "Error: Failed to set system locale" >&2
      return 1
    fi
  else
    # localectl needs a running systemd, write the file it would manage instead
    if ! echo "LANG=${DEFAULT_LOCALE}" | sudo tee /etc/locale.conf >/dev/null; then
      echo "Error: Failed to set system locale" >&2
      return 1
    fi
  fi
}

# Disable services that conflict with the headless remote desktop
function disable_conflicting_desktop_services() {
  local unit
  # Display managers cannot drive a physical display in WSL, and a previous xrdp setup would hold the RDP port
  for unit in gdm.service sddm.service xrdp.service xrdp-sesman.service; do
    if [[ -f "/usr/lib/systemd/system/${unit}" || -f "${SYSTEMD_SYSTEM_DIR}/${unit}" ]]; then
      if ! sudo systemctl disable "${unit}"; then
        echo "Error: Failed to disable ${unit}" >&2
        return 1
      fi
    fi
  done
}

# Install a service that makes /tmp/.X11-unix writable so the headless compositor can start Xwayland
function install_x11_unix_fix_service() {
  # WSLg mounts its own read-only /tmp/.X11-unix, keep its X0 socket reachable through a symlink
  if ! sudo tee "${SYSTEMD_SYSTEM_DIR}/${X11_UNIX_FIX_SERVICE}" >/dev/null <<'EOF'; then
[Unit]
Description=Make /tmp/.X11-unix writable for headless desktop sessions in WSL
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'if mountpoint -q /tmp/.X11-unix; then umount -l /tmp/.X11-unix; fi; if [ -L /tmp/.X11-unix ]; then rm -f /tmp/.X11-unix; fi; mkdir -p /tmp/.X11-unix; chmod 1777 /tmp/.X11-unix; if [ -S /mnt/wslg/.X11-unix/X0 ] && [ ! -e /tmp/.X11-unix/X0 ]; then ln -s /mnt/wslg/.X11-unix/X0 /tmp/.X11-unix/X0; fi'

[Install]
WantedBy=multi-user.target
EOF
    echo "Error: Failed to create ${X11_UNIX_FIX_SERVICE}" >&2
    return 1
  fi

  if ! sudo systemctl enable "${X11_UNIX_FIX_SERVICE}"; then
    echo "Error: Failed to enable ${X11_UNIX_FIX_SERVICE}" >&2
    return 1
  fi
}

# Enable avahi so the distribution can be reached as <hostname>.local
function enable_avahi_service() {
  if ! sudo systemctl enable avahi-daemon; then
    echo "Error: Failed to enable avahi-daemon service" >&2
    return 1
  fi
}

# Run a command with access to the user's D-Bus session bus, starting a temporary bus if none exists
function run_with_session_bus() {
  local user_bus
  user_bus="/run/user/$(id -u)/bus"

  if [[ -S "${user_bus}" ]]; then
    DBUS_SESSION_BUS_ADDRESS="unix:path=${user_bus}" "$@"
    return
  fi

  # Without a user manager the runtime directory may be missing or not writable, and dconf
  # silently drops the settings when it cannot use it
  local runtime_dir="${XDG_RUNTIME_DIR:-}"
  local temporary_runtime_dir=""
  if [[ -z "${runtime_dir}" || ! -d "${runtime_dir}" || ! -w "${runtime_dir}" ]]; then
    temporary_runtime_dir="$(mktemp -d)"
    runtime_dir="${temporary_runtime_dir}"
  fi

  local rc=0
  XDG_RUNTIME_DIR="${runtime_dir}" dbus-run-session -- "$@" || rc=$?

  if [[ -n "${temporary_runtime_dir}" ]]; then
    rm -rf "${temporary_runtime_dir}"
  fi

  return "${rc}"
}

# Generate a self-signed TLS certificate for the RDP server if it does not exist yet
function generate_tls_certificate() {
  local cert_dir="${1}"
  local hostname="${2}"

  if [[ -z "${cert_dir}" || -z "${hostname}" ]]; then
    echo "Error: Both cert_dir and hostname parameters are required" >&2
    return 1
  fi

  if [[ -f "${cert_dir}/rdp-tls.crt" && -f "${cert_dir}/rdp-tls.key" ]]; then
    return 0
  fi

  if ! mkdir -p "${cert_dir}"; then
    echo "Error: Failed to create ${cert_dir}" >&2
    return 1
  fi

  if ! openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
    -subj "/CN=${hostname}" \
    -keyout "${cert_dir}/rdp-tls.key" \
    -out "${cert_dir}/rdp-tls.crt" 2>/dev/null; then
    echo "Error: Failed to generate the TLS certificate" >&2
    return 1
  fi

  chmod 600 "${cert_dir}/rdp-tls.key"
}

# Configure the headless GNOME session and gnome-remote-desktop
function configure_gnome_remote_desktop() {
  local hostname="${1}"
  local rdp_port="${2}"
  local rdp_username="${3}"
  local rdp_password="${4}"

  if [[ -z "${hostname}" || -z "${rdp_port}" || -z "${rdp_username}" || -z "${rdp_password}" ]]; then
    echo "Error: hostname, rdp_port, rdp_username and rdp_password parameters are required" >&2
    return 1
  fi

  local config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
  local cert_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/gnome-remote-desktop"

  generate_tls_certificate "${cert_dir}" "${hostname}" || return 1

  echo "Configuring GNOME Remote Desktop..."

  if ! run_with_session_bus grdctl --headless rdp set-port "${rdp_port}" ||
    ! run_with_session_bus grdctl --headless rdp disable-port-negotiation ||
    ! run_with_session_bus grdctl --headless rdp set-tls-cert "${cert_dir}/rdp-tls.crt" ||
    ! run_with_session_bus grdctl --headless rdp set-tls-key "${cert_dir}/rdp-tls.key" ||
    ! run_with_session_bus grdctl --headless rdp disable-view-only; then
    echo "Error: Failed to configure GNOME Remote Desktop" >&2
    return 1
  fi

  if ! run_with_session_bus grdctl --headless rdp set-credentials "${rdp_username}" "${rdp_password}"; then
    echo "Error: Failed to set the GNOME Remote Desktop credentials" >&2
    return 1
  fi

  # grdctl also tries to enable the user unit through systemd, which is not reachable before the restart.
  # The setting is written regardless, and the unit is enabled below.
  if ! run_with_session_bus grdctl --headless rdp enable; then
    echo "Warning: grdctl could not enable the service now, it will be enabled at boot" >&2
    run_with_session_bus gsettings set org.gnome.desktop.remote-desktop.rdp.headless enable true || true
  fi

  # grdctl exits successfully even when the settings could not be stored, verify them
  if ! run_with_session_bus grdctl --headless status 2>/dev/null | grep -q "Port: ${rdp_port}$"; then
    echo "Error: GNOME Remote Desktop settings were not saved" >&2
    return 1
  fi

  # A headless session has no screen to lock or power off, keep it available for RDP
  run_with_session_bus gsettings set org.gnome.desktop.session idle-delay 0 || true
  run_with_session_bus gsettings set org.gnome.desktop.screensaver lock-enabled false || true
  run_with_session_bus gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type nothing || true

  # Skip GNOME Initial Setup and the welcome tour on the first login
  run_with_session_bus gsettings set org.gnome.shell welcome-dialog-last-shown-version "999" || true
  mkdir -p "${config_home}"
  echo "yes" >"${config_home}/gnome-initial-setup-done"

  # Start gnome-remote-desktop in headless mode inside the GNOME session
  local user_wants_dir="${config_home}/systemd/user/gnome-session.target.wants"
  if ! mkdir -p "${user_wants_dir}" ||
    ! ln -sf /usr/lib/systemd/user/gnome-remote-desktop-headless.service "${user_wants_dir}/"; then
    echo "Error: Failed to enable gnome-remote-desktop-headless.service" >&2
    return 1
  fi

  # gnome-remote-desktop crashes when it initializes Mesa's non-conformant D3D12 Vulkan driver (dzn)
  local grd_dropin_dir="${config_home}/systemd/user/gnome-remote-desktop-headless.service.d"
  if ! mkdir -p "${grd_dropin_dir}" ||
    ! cat >"${grd_dropin_dir}/wsl.conf" <<'EOF'; then
[Service]
Environment=VK_LOADER_DRIVERS_DISABLE=*dzn*
EOF
    echo "Error: Failed to configure gnome-remote-desktop-headless.service" >&2
    return 1
  fi

  # gnome-headless-session@.service has no [Install] section nor ordering, add them for WSL
  local session_dropin_dir="${SYSTEMD_SYSTEM_DIR}/gnome-headless-session@.service.d"
  if ! sudo mkdir -p "${session_dropin_dir}" ||
    ! sudo tee "${session_dropin_dir}/wsl.conf" >/dev/null <<EOF; then
[Unit]
After=systemd-user-sessions.service accounts-daemon.service ${X11_UNIX_FIX_SERVICE}
Wants=accounts-daemon.service ${X11_UNIX_FIX_SERVICE}

[Service]
RestartSec=5
# gdm-headless-login-session passes its environment to the session, like XRDP_SESSION for xrdp
Environment=GNOME_REMOTE_DESKTOP_SESSION=1
Environment=XDG_CURRENT_DESKTOP=GNOME
Environment=DESKTOP_SESSION=gnome
# GTK 4's Vulkan renderer runs out of memory on Mesa's D3D12 Vulkan driver (dzn)
Environment=GSK_RENDERER=gl
EOF
    echo "Error: Failed to configure gnome-headless-session@.service" >&2
    return 1
  fi

  if ! sudo mkdir -p "${SYSTEMD_SYSTEM_DIR}/multi-user.target.wants" ||
    ! sudo ln -sf /usr/lib/systemd/system/gnome-headless-session@.service \
      "${SYSTEMD_SYSTEM_DIR}/multi-user.target.wants/gnome-headless-session@${CURRENT_USER}.service"; then
    echo "Error: Failed to enable gnome-headless-session@${CURRENT_USER}.service" >&2
    return 1
  fi
}

# Configure the headless KDE Plasma session and KRdp
function configure_kde_remote_desktop() {
  local hostname="${1}"
  local rdp_port="${2}"

  if [[ -z "${hostname}" || -z "${rdp_port}" ]]; then
    echo "Error: Both hostname and rdp_port parameters are required" >&2
    return 1
  fi

  local config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
  local cert_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/krdpserver"

  generate_tls_certificate "${cert_dir}" "${hostname}" || return 1

  echo "Configuring KRdp..."

  # KRdp authenticates against the Linux user account through PAM. This only works with TLS security,
  # NLA fails with "Could not find user in SAM database" (also with --username/--password in KRdp 6.6)
  local -a krdp_settings=(
    "ListenPort ${rdp_port}"
    "SystemUserEnabled true"
    "AutogenerateCertificates false"
    "Certificate ${cert_dir}/rdp-tls.crt"
    "CertificateKey ${cert_dir}/rdp-tls.key"
    "Autostart true"
  )

  local setting key value
  for setting in "${krdp_settings[@]}"; do
    key="${setting%% *}"
    value="${setting#* }"
    if ! kwriteconfig6 --file krdpserverrc --group General --key "${key}" "${value}"; then
      echo "Error: Failed to set ${key} in krdpserverrc" >&2
      return 1
    fi
  done

  # A headless session has no screen to lock, keep it available for RDP
  kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false || true
  kwriteconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume false || true

  local user_unit_dir="${config_home}/systemd/user"

  # Run KWin with the virtual backend since WSL has no display for the session
  if ! mkdir -p "${user_unit_dir}/plasma-kwin_wayland.service.d" ||
    ! cat >"${user_unit_dir}/plasma-kwin_wayland.service.d/headless.conf" <<EOF; then
[Service]
ExecStart=
ExecStart=/usr/bin/kwin_wayland_wrapper --xwayland --virtual --no-lockscreen --width ${KDE_HEADLESS_WIDTH} --height ${KDE_HEADLESS_HEIGHT}
EOF
    echo "Error: Failed to configure plasma-kwin_wayland.service" >&2
    return 1
  fi

  # Use the Plasma screencast protocols, the portal would ask for an interactive approval
  if ! mkdir -p "${user_unit_dir}/app-org.kde.krdpserver.service.d" ||
    ! cat >"${user_unit_dir}/app-org.kde.krdpserver.service.d/headless.conf" <<EOF; then
[Service]
ExecStart=
ExecStart=/usr/bin/krdpserver --plasma --port ${rdp_port} --certificate ${cert_dir}/rdp-tls.crt --certificate-key ${cert_dir}/rdp-tls.key
Restart=on-failure
RestartSec=3
EOF
    echo "Error: Failed to configure app-org.kde.krdpserver.service" >&2
    return 1
  fi

  if ! mkdir -p "${user_unit_dir}/plasma-workspace.target.wants" ||
    ! ln -sf /usr/lib/systemd/user/app-org.kde.krdpserver.service "${user_unit_dir}/plasma-workspace.target.wants/"; then
    echo "Error: Failed to enable app-org.kde.krdpserver.service" >&2
    return 1
  fi

  # PAM stack for the session service, it only opens the session and never authenticates anyone
  if ! sudo tee "/etc/pam.d/${PLASMA_HEADLESS_PAM}" >/dev/null <<'EOF'; then
#%PAM-1.0
auth       required    pam_deny.so
account    required    pam_nologin.so
account    include     system-auth
password   required    pam_deny.so
session    optional    pam_loginuid.so
session    optional    pam_keyinit.so force revoke
session    include     system-auth
session    include     postlogin
EOF
    echo "Error: Failed to create /etc/pam.d/${PLASMA_HEADLESS_PAM}" >&2
    return 1
  fi

  # Logind session running startplasma-wayland, the equivalent of GNOME's gnome-headless-session@.service
  if ! sudo tee "${SYSTEMD_SYSTEM_DIR}/plasma-headless-session@.service" >/dev/null <<EOF; then
[Unit]
Description=KDE Plasma headless session for %i
After=systemd-user-sessions.service dbus.service ${X11_UNIX_FIX_SERVICE}
Wants=${X11_UNIX_FIX_SERVICE}

[Service]
Type=simple
User=%i
PAMName=${PLASMA_HEADLESS_PAM}
WorkingDirectory=~
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_SESSION_CLASS=user
Environment=XDG_SESSION_DESKTOP=KDE
Environment=XDG_CURRENT_DESKTOP=KDE
Environment=DESKTOP_SESSION=plasma
Environment=KRDP_SESSION=1
ExecStart=/bin/sh -c 'export DBUS_SESSION_BUS_ADDRESS="unix:path=\$\${XDG_RUNTIME_DIR}/bus"; exec /usr/bin/startplasma-wayland'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    echo "Error: Failed to create plasma-headless-session@.service" >&2
    return 1
  fi

  if ! sudo systemctl enable "plasma-headless-session@${CURRENT_USER}.service"; then
    echo "Error: Failed to enable plasma-headless-session@${CURRENT_USER}.service" >&2
    return 1
  fi
}

# Mask conflicting systemd services
function mask_conflicting_services() {
  echo "Masking conflicting services..."

  if ! sudo ln -sf /dev/null /etc/systemd/system/systemd-resolved.service; then
    echo "Error: Failed to mask systemd-resolved.service" >&2
    return 1
  fi

  if ! sudo ln -sf /dev/null /etc/systemd/system/systemd-networkd.service; then
    echo "Error: Failed to mask systemd-networkd.service" >&2
    return 1
  fi

  if ! sudo ln -sf /dev/null /etc/systemd/system/NetworkManager.service; then
    echo "Error: Failed to mask NetworkManager.service" >&2
    return 1
  fi

  if ! sudo ln -sf /dev/null /etc/systemd/system/NetworkManager-wait-online.service; then
    echo "Error: Failed to mask NetworkManager-wait-online.service" >&2
    return 1
  fi

  if ! sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-setup.service; then
    echo "Error: Failed to mask systemd-tmpfiles-setup.service" >&2
    return 1
  fi

  if ! sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-clean.service; then
    echo "Error: Failed to mask systemd-tmpfiles-clean.service" >&2
    return 1
  fi

  if ! sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-clean.timer; then
    echo "Error: Failed to mask systemd-tmpfiles-clean.timer" >&2
    return 1
  fi

  if ! sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-setup-dev-early.service; then
    echo "Error: Failed to mask systemd-tmpfiles-setup-dev-early.service" >&2
    return 1
  fi

  if ! sudo ln -sf /dev/null /etc/systemd/system/systemd-tmpfiles-setup-dev.service; then
    echo "Error: Failed to mask systemd-tmpfiles-setup-dev.service" >&2
    return 1
  fi

  if ! sudo ln -sf /dev/null /etc/systemd/system/tmp.mount; then
    echo "Error: Failed to mask tmp.mount" >&2
    return 1
  fi
}

# Check that the script is running inside WSL2; exit with a message if not
function check_wsl2() {
  if [[ -z "${WSL2:-}" ]]; then
    if command -v whiptail >/dev/null 2>&1; then
      whiptail --backtitle "${PENGWIN_SETUP_TITLE}" \
        --title "WSL2 Required" \
        --msgbox "This setup requires WSL2.\n\nPlease migrate to WSL2 before running this script.\nSee: https://aka.ms/wsl2" \
        10 60
    else
      >&2 printf '%s\n\n%s\n%s\n' \
        "This setup requires WSL2." \
        "Please migrate to WSL2 before running this script." \
        "See: https://aka.ms/wsl2"
    fi
    return 1
  fi
}

# Check that the script runs as the regular user that will own the desktop session
function check_not_root() {
  if [[ ${EUID} -eq 0 ]]; then
    >&2 echo "Error: Run this script as your regular user, not as root. It uses sudo when needed."
    return 1
  fi
}

# Terminate WSL distribution
function terminate_wsl_distribution() {
  if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    # Save shell history before terminating WSL to prevent history loss
    history -a 2>/dev/null || true
    wsl.exe --terminate "${WSL_DISTRO_NAME}"
  else
    echo "Warning: WSL_DISTRO_NAME not set, skipping WSL termination" >&2
  fi
}

# Fedora 43 and older use the Xorg-based desktop setup.
function run_legacy_desktop_setup() {
  local fedora_version
  fedora_version=$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")

  if [[ ${fedora_version} =~ ^[0-9]+$ ]] && ((fedora_version <= 43)); then
    local xorg_script
    xorg_script="$(dirname -- "${BASH_SOURCE[0]}")/install-desktop-xorg.sh"
    if [[ ! -x ${xorg_script} ]]; then
      echo "Error: Fedora ${fedora_version} requires ${xorg_script}, but it is unavailable" >&2
      return 1
    fi

    exec "${xorg_script}" "$@"
  fi
}

# Main setup function
function main() {
  run_legacy_desktop_setup "$@" || return 1

  echo "Starting Fedora Remix Desktop Setup..."

  # Ensure we are running inside WSL2 as a regular user
  check_wsl2 || exit 1
  check_not_root || exit 1

  # Run update script if available
  run_update_script

  # Install UI dependencies
  install_ui_dependencies || return 1

  # Get user inputs
  local hostname rdp_port desktop_choice rdp_username rdp_password=""
  hostname=$(get_hostname_input) || return 1
  rdp_port=$(get_rdp_port_input) || return 1
  desktop_choice=$(get_desktop_choice) || return 1

  if [[ ${desktop_choice} == "GNOME" ]]; then
    rdp_username=$(get_rdp_username_input) || return 1
    rdp_password=$(get_rdp_password_input) || return 1
  else
    rdp_username="${CURRENT_USER}"
  fi

  echo "Configuration:"
  echo "  Hostname: ${hostname}"
  echo "  RDP Port: ${rdp_port}"
  echo "  Desktop: ${desktop_choice}"
  echo "  RDP Username: ${rdp_username}"

  local systemd_pid
  systemd_pid="$(ps -C systemd -o pid= | head -n1 || true)"

  # Install and configure components
  install_required_tools || return 1
  configure_wsl_settings "${hostname}" || return 1
  install_desktop_environment "${desktop_choice}" || return 1
  configure_system_locale "${systemd_pid}" || return 1
  disable_conflicting_desktop_services || return 1
  install_x11_unix_fix_service || return 1
  enable_avahi_service || return 1

  if [[ ${desktop_choice} == "GNOME" ]]; then
    configure_gnome_remote_desktop "${hostname}" "${rdp_port}" "${rdp_username}" "${rdp_password}" || return 1
  else
    configure_kde_remote_desktop "${hostname}" "${rdp_port}" || return 1
  fi

  # Mask conflicting services for WSL
  mask_conflicting_services || return 1

  # Get IP address for the summary
  local ip_address
  ip_address=$(get_wsl_ip_address)

  # Show final configuration summary
  show_configuration_summary "${hostname}" "${rdp_port}" "${desktop_choice}" "${rdp_username}" "${ip_address}"

  echo "Setup completed successfully!"
  echo "Terminating WSL distribution to apply changes..."
  terminate_wsl_distribution
}

main "$@"
