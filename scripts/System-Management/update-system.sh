#!/usr/bin/env bash
set -Eeuo pipefail

info() { printf '\n\033[1;36m[INFO]\033[0m %s\n' "$*"; }
error() { printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

if [[ "$(uname -s)" != Linux ]] || [[ ! -r /etc/os-release ]]; then
    error "This script requires a supported Linux system with /etc/os-release."
    exit 1
fi

. /etc/os-release
case "${ID,,}" in
    ubuntu|debian) ;;
    *) error "Supported distributions: Ubuntu and Debian. Detected: ${PRETTY_NAME:-$ID}."; exit 1 ;;
esac

if ! command -v apt-get >/dev/null 2>&1; then
    error "apt-get was not found."
    exit 1
fi

if (( EUID == 0 )); then
    SUDO=()
elif command -v sudo >/dev/null 2>&1; then
    sudo -v
    SUDO=(sudo)
else
    error "Run as root or install sudo."
    exit 1
fi

printf 'This will refresh APT package indexes and upgrade installed packages.\n'
printf 'Review the package manager output before confirming any additional prompts.\n'
read -r -p "Continue? [y/N] " answer
case "$answer" in
    y|Y|yes|YES) ;;
    *) info "Cancelled."; exit 0 ;;
esac

info "Refreshing package indexes..."
"${SUDO[@]}" apt-get update

info "Upgrading installed packages..."
"${SUDO[@]}" apt-get upgrade

info "Package upgrade completed."
if command -v needrestart >/dev/null 2>&1; then
    info "Checking whether services or a reboot may be required..."
    "${SUDO[@]}" needrestart -r l || true
elif [[ -f /var/run/reboot-required ]]; then
    printf '\nA reboot is required to complete some updates.\n'
fi
