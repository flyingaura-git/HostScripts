#!/usr/bin/env bash
#
# HostScripts - Dependency installer
# Supported distributions: Ubuntu and Debian
#
set -Eeuo pipefail

readonly SCRIPT_NAME="dependencies.sh"
readonly MANIFEST_URL="https://raw.githubusercontent.com/flyingaura-git/HostScripts/refs/heads/main/dependencies.txt"

log()  { printf '\033[1;34m[HostScripts]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARNING]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: sudo bash ${SCRIPT_NAME} [OPTION]

Fetch dependencies.txt from the HostScripts GitHub repository, then
install or check the APT packages listed in that remote manifest.

Options:
  --check     Check installed packages without installing anything.
  -h, --help  Show this help message.
EOF
}

CHECK_ONLY=false
case "${1:-}" in
    "") ;;
    --check) CHECK_ONLY=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
esac
[[ $# -le 1 ]] || die "Only one option may be provided."
[[ $EUID -eq 0 ]] || die "Run as root: sudo bash ${SCRIPT_NAME}"
[[ -r /etc/os-release ]] || die "Cannot identify the operating system."

# shellcheck disable=SC1091
source /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
    *" ubuntu "*|*" debian "*) ;;
    *) die "Unsupported distribution: ${PRETTY_NAME:-${ID:-unknown}}. Ubuntu and Debian are supported." ;;
esac

command -v apt-get >/dev/null 2>&1 || die "apt-get was not found."
command -v dpkg-query >/dev/null 2>&1 || die "dpkg-query was not found."

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
MANIFEST="${TEMP_DIR}/dependencies.txt"

log "Downloading dependency manifest from GitHub..."
if command -v curl >/dev/null 2>&1; then
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 10 "$MANIFEST_URL" --output "$MANIFEST" \
        || die "Could not download the dependency manifest."
elif command -v wget >/dev/null 2>&1; then
    wget --quiet --tries=3 --timeout=10 "$MANIFEST_URL" --output-document="$MANIFEST" \
        || die "Could not download the dependency manifest."
else
    die "curl or wget is required to download the dependency manifest."
fi
[[ -s "$MANIFEST" ]] || die "The downloaded dependency manifest is empty."

PACKAGES=()
while IFS='|' read -r package _purpose || [[ -n "${package:-}" ]]; do
    # Remove comments, carriage returns, and surrounding whitespace.
    package="${package%%#*}"
    package="${package//$'\r'/}"
    package="$(printf '%s' "$package" | xargs)"
    [[ -z "$package" ]] && continue
    [[ "$package" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || die "Invalid package name in remote manifest: $package"
    PACKAGES+=("$package")
done < "$MANIFEST"

(("${#PACKAGES[@]}" > 0)) || die "No valid dependencies were found in the remote manifest."

log "Detected: ${PRETTY_NAME:-${ID:-unknown}}"
log "Dependencies defined: ${#PACKAGES[@]}"

MISSING=()
for package in "${PACKAGES[@]}"; do
    status="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)"
    [[ "$status" == "install ok installed" ]] || MISSING+=("$package")
done

log "Dependencies missing: ${#MISSING[@]}"
if (("${#MISSING[@]}" > 0)); then
    printf '  - %s\n' "${MISSING[@]}"
fi

if [[ "$CHECK_ONLY" == true ]]; then
    if (("${#MISSING[@]}" > 0)); then
        warn "Run 'sudo bash ${SCRIPT_NAME}' to install missing dependencies."
        exit 1
    fi
    log "All HostScripts dependencies are installed."
    exit 0
fi

if (("${#MISSING[@]}" == 0)); then
    log "All HostScripts dependencies are already installed."
    exit 0
fi

log "Updating APT package indexes..."
export DEBIAN_FRONTEND=noninteractive
apt-get update

AVAILABLE=()
UNAVAILABLE=()
for package in "${MISSING[@]}"; do
    candidate="$(apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
        AVAILABLE+=("$package")
    else
        UNAVAILABLE+=("$package")
    fi
done

if (("${#UNAVAILABLE[@]}" > 0)); then
    warn "These manifest packages have no APT candidate on this system:"
    printf '  - %s\n' "${UNAVAILABLE[@]}" >&2
fi
(("${#AVAILABLE[@]}" > 0)) || die "None of the missing dependencies are available from the configured APT repositories."

log "Installing available missing dependencies..."
apt-get install -y --no-install-recommends "${AVAILABLE[@]}"

log "Verifying installation..."
FAILED=()
for package in "${AVAILABLE[@]}"; do
    status="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)"
    [[ "$status" == "install ok installed" ]] || FAILED+=("$package")
done

if (("${#FAILED[@]}" > 0)); then
    printf '  - %s\n' "${FAILED[@]}" >&2
    die "Some dependencies could not be verified."
fi

if (("${#UNAVAILABLE[@]}" > 0)); then
    die "Some dependencies were unavailable. Update dependencies.txt or configure the required APT repository."
fi

log "All HostScripts dependencies are installed successfully."
