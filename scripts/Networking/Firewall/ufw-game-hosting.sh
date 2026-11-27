#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="Game Hosting Node Firewall Setup"

info()    { printf '\n\033[1;36m[INFO]\033[0m %s\n' "$*"; }
success() { printf '\n\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn()    { printf '\n\033[1;33m[WARNING]\033[0m %s\n' "$*" >&2; }
error()   { printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

if [[ "$(uname -s)" != "Linux" ]] || [[ ! -r /etc/os-release ]]; then
    error "This script requires Linux with /etc/os-release."
    exit 1
fi

. /etc/os-release
case "${ID,,}" in
    ubuntu|debian) ;;
    *)
        error "Supported distributions: Ubuntu and Debian. Detected: ${PRETTY_NAME:-$ID}."
        exit 1
        ;;
esac

if (( EUID == 0 )); then
    SUDO=()
elif command -v sudo >/dev/null 2>&1; then
    sudo -v
    SUDO=(sudo)
else
    error "Run as root or install sudo first."
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    error "apt-get is required to install UFW on this distribution."
    exit 1
fi

printf '\n\033[1;35m%s\033[0m\n' "$SCRIPT_NAME"
printf '\nThis setup will ensure UFW is installed and add these inbound rules:\n'
printf '\n  TCP: 22, 80, 443, 8080, 2022, 25500-25600, 19100-19500\n'
printf '  UDP: 25500-25600, 19100-19500\n'
printf '\nPort purpose:\n'
printf '  22             SSH administration\n'
printf '  80 / 443       HTTP and HTTPS (including web/ACME use)\n'
printf '  8080           Common Pterodactyl Wings API port (may be customized)\n'
printf '  2022           Common Pterodactyl Wings SFTP port (may be customized)\n'
printf '  25500-25600    Game allocation range\n'
printf '  19100-19500    Common UDP game allocation range\n'
printf '\nIMPORTANT: This enables UFW. Other inbound ports not allowed by your existing\n'
printf 'firewall policy may become unreachable. Existing UFW default policies are not changed.\n'
printf 'If SSH uses a custom port, add that port before proceeding.\n'

if [[ -t 0 ]]; then
    read -r -p "Continue with firewall setup? [y/N] " answer
else
    error "Interactive confirmation is required. Run this script in a terminal."
    exit 1
fi

case "$answer" in
    y|Y|yes|YES) ;;
    *) info "Cancelled. No firewall changes were made."; exit 0 ;;
esac

if ! command -v ufw >/dev/null 2>&1; then
    info "UFW is not installed. Installing..."
    "${SUDO[@]}" apt-get update
    DEBIAN_FRONTEND=noninteractive "${SUDO[@]}" apt-get install -y ufw
fi

if ! command -v ufw >/dev/null 2>&1; then
    error "UFW installation did not provide the ufw command."
    exit 1
fi

info "Adding required TCP rules..."
"${SUDO[@]}" ufw allow 22/tcp
"${SUDO[@]}" ufw allow 80/tcp
"${SUDO[@]}" ufw allow 443/tcp
"${SUDO[@]}" ufw allow 8080/tcp
"${SUDO[@]}" ufw allow 2022/tcp
"${SUDO[@]}" ufw allow 25500:25600/tcp
"${SUDO[@]}" ufw allow 19100:19500/tcp

info "Adding required UDP rules..."
"${SUDO[@]}" ufw allow 25500:25600/udp
"${SUDO[@]}" ufw allow 19100:19500/udp

if "${SUDO[@]}" ufw status | grep -q '^Status: active'; then
    success "UFW is already active. The requested rules have been added."
else
    warn "UFW is currently inactive. It will now be enabled."
    "${SUDO[@]}" ufw --force enable
fi

printf '\n'
"${SUDO[@]}" ufw status verbose
success "Game Hosting Node Firewall Setup completed."
printf '\nNote: Wings ports can be customized in the Wings configuration. Make sure\n'
printf 'the allowed ports match your actual Wings and game allocation configuration.\n'
