#!/bin/bash
#
# install-desktop.sh - Fedora Remix Desktop Setup Script
#
# This script provides an interactive setup for configuring a desktop environment
# in Fedora Remix WSL distribution. It handles user input for hostname,
# RDP port, listen port, and desktop environment selection.
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
readonly DEFAULT_LISTEN_PORT="3346"
readonly DEFAULT_LOCALE="en_US.UTF-8"

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
  local listen_port="${3}"
  local desktop_choice="${4}"
  local ip_address="${5}"

  local summary_text=""
  summary_text+="Setup completed successfully!\n\n"
  summary_text+="CONFIGURATION SUMMARY:\n"
  summary_text+="=====================\n\n"
  summary_text+="Hostname: ${hostname}\n"
  summary_text+="Desktop Environment: ${desktop_choice}\n"
  summary_text+="RDP Port: ${rdp_port}\n"
  summary_text+="Session Manager Port: ${listen_port}\n"
  summary_text+="WSL IP Address: ${ip_address}\n\n"
  summary_text+="CONNECTION INFORMATION:\n"
  summary_text+="======================\n\n"
  summary_text+="Primary connection (using hostname):\n"
  summary_text+="  ${hostname}:${rdp_port}\n\n"
  summary_text+="Fallback connection (using IP address):\n"
  summary_text+="  ${ip_address}:${rdp_port}\n\n"
  summary_text+="Use these connection details in your RDP client.\n"
  summary_text+="If hostname resolution fails, use the IP address.\n\n"
  summary_text+="The WSL distribution will now restart to apply changes."

  whiptail --backtitle "${PENGWIN_SETUP_TITLE}" \
    --title "Setup Complete - Configuration Summary" \
    --msgbox "${summary_text}" 25 80
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
    --inputbox "RDP Port: " 8 50 "${DEFAULT_RDP_PORT}" 3>&1 1>&2 2>&3); then
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
  echo "${port}"
}

# Get listen port from user input
function get_listen_port_input() {
  local listen_port
  if ! listen_port=$(whiptail --backtitle "${PENGWIN_SETUP_TITLE}" \
    --title "Enter the desired session manager Listen Port" \
    --inputbox "Listen Port: " 8 70 "${DEFAULT_LISTEN_PORT}" 3>&1 1>&2 2>&3); then
    echo "Error: Listen port input cancelled" >&2
    return 1
  fi

  if [[ -z "${listen_port}" ]]; then
    echo "Error: Listen port cannot be empty" >&2
    return 1
  fi

  # Validate that listen_port is a valid integer port in the range 1-65535
  if ! [[ "${listen_port}" =~ ^[0-9]+$ ]]; then
    echo "Error: Listen port must be a numeric value" >&2
    return 1
  fi

  if (( 10#${listen_port} < 1 || 10#${listen_port} > 65535 )); then
    echo "Error: Listen port must be in the range 1-65535" >&2
    return 1
  fi

  echo "${listen_port}"
}

# Get desktop environment selection from user
function get_desktop_choice() {
  local desktop_choice
  if ! desktop_choice=$(whiptail --backtitle "${PENGWIN_SETUP_TITLE}" \
    --title "Desktop Selection" --radiolist --separate-output \
    "Choose your desired Desktop Environment\n[SPACE to select, ENTER to confirm]:" \
    12 45 4 \
    "GNOME" "GNOME Desktop Environment   " on \
    "KDE" "KDE Plasma Desktop" off \
    "Xfce" "XFCE 4 Desktop" off \
    "LXDE" "LXDE Desktop" off 3>&1 1>&2 2>&3); then
    echo "Error: Desktop selection cancelled" >&2
    return 1
  fi

  if [[ -z "${desktop_choice}" ]]; then
    echo "Error: No desktop environment selected" >&2
    return 1
  fi

  echo "${desktop_choice}"
}

# Install required tools
function install_required_tools() {
  if ! sudo dnf -y install crudini; then
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

# Install desktop environment
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
  desktop_group["Xfce"]="xfce-desktop"
  desktop_group["LXDE"]="lxde-desktop"

  local group_to_install="${desktop_group[${desktop_choice}]:-}"

  if [[ -z "${group_to_install}" ]]; then
    echo "Error: Unknown desktop environment: ${desktop_choice}" >&2
    return 1
  fi

  if ! sudo dnf -y group install "${group_to_install}"; then
    echo "Error: Failed to install ${desktop_choice} desktop environment" >&2
    return 1
  fi

  # Install additional packages for KDE
  if [[ ${desktop_choice} == "KDE" ]]; then
    if ! sudo dnf -y install plasma-workspace-x11; then
      echo "Error: Failed to install plasma-workspace-x11" >&2
      return 1
    fi
  fi
}

# Configure X session
function configure_x_session() {
  local desktop_choice="${1}"

  if [[ -z "${desktop_choice}" ]]; then
    echo "Error: desktop_choice parameter is required" >&2
    return 1
  fi

  # Desktop environment executable mappings
  declare -A desktop_execs
  desktop_execs["GNOME"]="gnome-session"
  desktop_execs["KDE"]="startplasma-x11"
  desktop_execs["Xfce"]="startxfce4"
  desktop_execs["LXDE"]="startlxde"

  local desktop_exec="${desktop_execs[${desktop_choice}]:-}"

  if [[ -z "${desktop_exec}" ]]; then
    echo "Error: Unknown desktop environment: ${desktop_choice}" >&2
    return 1
  fi

  local desktop_exec_path
  if ! desktop_exec_path=$(command -v "${desktop_exec}"); then
    echo "Error: Desktop executable not found: ${desktop_exec}" >&2
    return 1
  fi

  # Create .xsession file
  if ! echo "exec ${desktop_exec_path}" > "${HOME}/.xsession"; then
    echo "Error: Failed to create .xsession file" >&2
    return 1
  fi

  if ! chmod +x "${HOME}/.xsession"; then
    echo "Error: Failed to make .xsession executable" >&2
    return 1
  fi
}

# Configure system locale
function configure_system_locale() {
  if ! sudo localectl set-locale "LANG=${DEFAULT_LOCALE}"; then
    echo "Error: Failed to set system locale" >&2
    return 1
  fi
}

# Install and configure RDP services
function install_rdp_services() {
  if ! sudo dnf -y install xrdp avahi xorg-x11-xinit-session tigervnc-server; then
    echo "Error: Failed to install RDP services" >&2
    return 1
  fi

  if ! sudo systemctl enable xrdp; then
    echo "Error: Failed to enable xrdp service" >&2
    return 1
  fi

  if ! sudo systemctl enable avahi-daemon; then
    echo "Error: Failed to enable avahi-daemon service" >&2
    return 1
  fi
}

# Configure RDP settings
function configure_rdp_settings() {
  local rdp_port="${1}"
  local listen_port="${2}"

  if [[ -z "${rdp_port}" || -z "${listen_port}" ]]; then
    echo "Error: Both rdp_port and listen_port parameters are required" >&2
    return 1
  fi

  # Configure RDP port
  if ! sudo sed -i "s/port=3389/port=${rdp_port}/" /etc/xrdp/xrdp.ini; then
    echo "Error: Failed to configure RDP port" >&2
    return 1
  fi

  # Configure session manager listen port
  if ! sudo sed -i "s/ListenPort=3350/ListenPort=${listen_port}/" /etc/xrdp/sesman.ini; then
    echo "Error: Failed to configure session manager listen port" >&2
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

# Main setup function
function main() {
  echo "Starting Fedora Remix Desktop Setup..."

  # Ensure we are running inside WSL2
  check_wsl2 || exit 1

  # Run update script if available
  run_update_script

  # Install UI dependencies
  install_ui_dependencies || return 1

  # Get user inputs
  local hostname rdp_port listen_port desktop_choice
  hostname=$(get_hostname_input) || return 1
  rdp_port=$(get_rdp_port_input) || return 1
  listen_port=$(get_listen_port_input) || return 1
  desktop_choice=$(get_desktop_choice) || return 1

  echo "Configuration:"
  echo "  Hostname: ${hostname}"
  echo "  RDP Port: ${rdp_port}"
  echo "  Listen Port: ${listen_port}"
  echo "  Desktop: ${desktop_choice}"

  local systemd_pid
  systemd_pid="$(ps -C systemd -o pid= | head -n1 || true)"

  # Install and configure components
  install_required_tools || return 1
  configure_wsl_settings "${hostname}" || return 1
  install_desktop_environment "${desktop_choice}" || return 1
  configure_x_session "${desktop_choice}" || return 1

  if [[ -n "${systemd_pid}" ]]; then
    configure_system_locale || return 1
  fi

  install_rdp_services || return 1
  configure_rdp_settings "${rdp_port}" "${listen_port}" || return 1
  
  # Mask conflicting services for WSL
  mask_conflicting_services || return 1

  # Get IP address for the summary
  local ip_address
  ip_address=$(get_wsl_ip_address)

  # Show final configuration summary
  show_configuration_summary "${hostname}" "${rdp_port}" "${listen_port}" "${desktop_choice}" "${ip_address}"

  echo "Setup completed successfully!"
  echo "Terminating WSL distribution to apply changes..."
  terminate_wsl_distribution
}

main "$@"
