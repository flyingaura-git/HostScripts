#!/usr/bin/env bash
#
# HostScripts - Remote launcher
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/flyingaura-git/HostScripts/main/main.sh | bash
#
set -Eeuo pipefail

readonly DEPENDENCIES_URL="https://raw.githubusercontent.com/flyingaura-git/HostScripts/main/dependencies.sh"
readonly MAIN_URL="https://raw.githubusercontent.com/flyingaura-git/HostScripts/main/main.py"

log()  { printf '\033[1;34m[HostScripts]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required to fetch HostScripts. Install curl and retry."

log "Running the dependency installer..."
if [[ "$EUID" -eq 0 ]]; then
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 10 "$DEPENDENCIES_URL" | bash
else
    command -v sudo >/dev/null 2>&1 || die "sudo is required. Run this launcher as root or install sudo."
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 10 "$DEPENDENCIES_URL" | sudo bash
fi

log "Launching HostScripts..."
command -v python3 >/dev/null 2>&1 || die "Python 3 is not installed."

MAIN_SOURCE="$(curl --fail --silent --show-error --location --retry 3 --connect-timeout 10 "$MAIN_URL")" \
    || die "Could not fetch main.py from GitHub."
[[ -n "$MAIN_SOURCE" ]] || die "The downloaded main.py is empty."

# Use -c rather than stdin so the CLI retains access to the terminal.
exec python3 -c "$MAIN_SOURCE" "$@"
