#!/usr/bin/env bash
#
# HostScripts - Main launcher
#
# Checks project dependencies, installs them when needed, then starts main.py.
#
# Usage:
#   bash main.sh
#   chmod +x main.sh && ./main.sh
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPENDENCY_SCRIPT="$SCRIPT_DIR/depends.sh"
MAIN_SCRIPT="$SCRIPT_DIR/main.py"

log()  { printf '\033[1;34m[HostScripts]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f "$DEPENDENCY_SCRIPT" ]] || die "Dependency installer not found: $DEPENDENCY_SCRIPT"
[[ -f "$MAIN_SCRIPT" ]] || die "Main application not found: $MAIN_SCRIPT"

command -v python3 >/dev/null 2>&1 || die "Python 3 is not installed. Install Python 3, then run this launcher again."

run_as_root() {
    if [[ "$EUID" -eq 0 ]]; then
        bash "$DEPENDENCY_SCRIPT" "$@"
    else
        command -v sudo >/dev/null 2>&1 || die "sudo is required to check or install system dependencies. Run this launcher as root or install sudo."
        sudo bash "$DEPENDENCY_SCRIPT" "$@"
    fi
}

log "Checking HostScripts dependencies..."

if run_as_root --check; then
    log "All dependencies are available."
else
    log "Dependencies are missing or the check failed. Starting the dependency installer..."
    run_as_root
    log "Checking dependencies again..."
    run_as_root --check || die "Dependency verification failed. Resolve the errors above and try again."
fi

log "Starting HostScripts..."
exec python3 "$MAIN_SCRIPT" "$@"
