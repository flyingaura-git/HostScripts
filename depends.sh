#!/usr/bin/env bash
#
# HostScripts - Common dependency installer
# Supported systems: Ubuntu and Debian
#
# Usage:
#   sudo bash depends.sh
#   sudo bash depends.sh --check
#
set -Eeuo pipefail

readonly SCRIPT_NAME="depends.sh"

readonly PACKAGES=(
    bash
    ca-certificates
    coreutils
    curl
    dnsutils
    findutils
    gawk
    git
    grep
    gzip
    iproute2
    iputils-ping
    jq
    less
    lsof
    net-tools
    openssl
    procps
    psmisc
    rsync
    sed
    tar
    unzip
    util-linux
    wget
    xz-utils
)

log()  { printf '\033[1;34m[HostScripts]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARNING]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: sudo bash ${SCRIPT_NAME} [OPTION]

Install or check the common system dependencies used by HostScripts.

Options:
  --check    Check whether all dependencies are installed; do not install.
  -h, --help Show this help message.
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

[[ $EUID -eq 0 ]] || die "Run this script as root: sudo bash ${SCRIPT_NAME}"

[[ -r /etc/os-release ]] || die "Cannot identify the operating system (/etc/os-release missing)."
# shellcheck disable=SC1091
source /etc/os-release

OS_ID="${ID:-unknown}"
OS_LIKE="${ID_LIKE:-}"

case " $OS_ID $OS_LIKE " in
    *" ubuntu "*|*" debian "*) ;;
    *) die "Unsupported distribution: ${PRETTY_NAME:-$OS_ID}. Only Ubuntu and Debian are supported." ;;
esac

command -v apt-get >/dev/null 2>&1 || die "apt-get was not found."

missing_packages=()
for package in "${PACKAGES[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q '^install ok installed$'; then
        missing_packages+=("$package")
    fi
done

log "Detected: ${PRETTY_NAME:-$OS_ID}"
log "Dependencies defined: ${#PACKAGES[@]}"
log "Dependencies missing: ${#missing_packages[@]}"

if (("${#missing_packages[@]}" == 0)); then
    log "All HostScripts dependencies are already installed."
    exit 0
fi

printf '  - %s\n' "${missing_packages[@]}"

if [[ "$CHECK_ONLY" == true ]]; then
    warn "Dependency check failed. Run 'sudo bash ${SCRIPT_NAME}' to install missing packages."
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

log "Updating APT package indexes..."
apt-get update

log "Installing missing dependencies..."
apt-get install -y --no-install-recommends "${missing_packages[@]}"

log "Verifying installation..."
failed=()
for package in "${missing_packages[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q '^install ok installed$'; then
        failed+=("$package")
    fi
done

if (("${#failed[@]}" > 0)); then
    printf '  - %s\n' "${failed[@]}" >&2
    die "Some dependencies could not be verified."
fi

log "All HostScripts dependencies are installed successfully."
