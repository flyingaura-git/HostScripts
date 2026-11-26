#!/usr/bin/env bash
set -Eeuo pipefail

info() { printf '\n\033[1;36m[INFO]\033[0m %s\n' "$*"; }
error() { printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

if [[ "$(uname -s)" != Linux ]] || [[ ! -r /etc/os-release ]]; then
    error "This script requires Linux with /etc/os-release."
    exit 1
fi
. /etc/os-release
case "${ID,,}" in
    ubuntu|debian) ;;
    *) error "Supported distributions: Ubuntu and Debian."; exit 1 ;;
esac

if (( EUID == 0 )); then
    SUDO=()
elif command -v sudo >/dev/null 2>&1; then
    sudo -v
    SUDO=(sudo)
else
    error "Run as root or install sudo."
    exit 1
fi

printf 'This cleanup performs only the following actions:\n'
printf '  - Clear downloaded APT package cache\n'
printf '  - Remove packages installed as dependencies that are no longer needed (APT autoremove)\n'
printf '  - Vacuum systemd journal entries older than 14 days, if journalctl is available\n'
printf '\nIt will not delete user files, application data, or arbitrary log files.\n'
read -r -p "Continue? [y/N] " answer
case "$answer" in
    y|Y|yes|YES) ;;
    *) info "Cancelled."; exit 0 ;;
esac

info "Cleaning APT package cache..."
"${SUDO[@]}" apt-get clean

info "Removing unused APT dependencies..."
"${SUDO[@]}" apt-get autoremove

if command -v journalctl >/dev/null 2>&1; then
    info "Vacuuming system journal entries older than 14 days..."
    "${SUDO[@]}" journalctl --vacuum-time=14d
else
    info "journalctl not found; skipping journal cleanup."
fi

info "Cleanup completed. Current root filesystem usage:"
df -h /
