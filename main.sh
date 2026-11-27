#!/usr/bin/env bash
#
# HostScripts - Remote one-line launcher
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/flyingaura-git/HostScripts/refs/heads/main/main.sh | bash
#
set -Eeuo pipefail

readonly BASE_URL="https://raw.githubusercontent.com/flyingaura-git/HostScripts/refs/heads/main"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

log()  { printf '\033[1;34m[HostScripts]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

if command -v curl >/dev/null 2>&1; then
    download() { curl -fsSL --retry 3 --connect-timeout 10 "$BASE_URL/$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
    download() { wget -q --tries=3 --timeout=10 "$BASE_URL/$1" -O "$2"; }
else
    die "Neither curl nor wget is installed. Install one and retry."
fi

log "Fetching HostScripts launcher files..."
download "depends.sh" "$TEMP_DIR/depends.sh" || die "Could not download depends.sh."
download "main.py" "$TEMP_DIR/main.py" || die "Could not download main.py."

[[ -s "$TEMP_DIR/depends.sh" ]] || die "Downloaded depends.sh is empty."
[[ -s "$TEMP_DIR/main.py" ]] || die "Downloaded main.py is empty."

command -v python3 >/dev/null 2>&1 || die "Python 3 is not installed. Install Python 3, then run this launcher again."

run_as_root() {
    if [[ "$EUID" -eq 0 ]]; then
        bash "$TEMP_DIR/depends.sh" "$@"
    else
        command -v sudo >/dev/null 2>&1 || die "sudo is required to install dependencies. Run as root or install sudo."
        sudo bash "$TEMP_DIR/depends.sh" "$@"
    fi
}

log "Checking HostScripts dependencies..."
if run_as_root --check; then
    log "Dependencies are already installed."
else
    log "Installing missing dependencies..."
    run_as_root
    log "Verifying dependencies..."
    run_as_root --check || die "Dependency verification failed. Check the errors above."
fi

log "Launching HostScripts..."
python3 "$TEMP_DIR/main.py" "$@"
