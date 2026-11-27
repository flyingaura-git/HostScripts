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
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly MANIFEST="${SCRIPT_DIR}/dependencies.txt"

log()  { printf '\033[1;34m[HostScripts]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARNING]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: sudo bash ${SCRIPT_NAME} [OPTION]

Install or check the APT dependencies listed in dependencies.txt.

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
[[ -r "$MANIFEST" ]] || die "Dependency manifest not found: $MANIFEST"

# shellcheck disable=SC1091
source /etc/os-release
OS_ID="${ID:-unknown}"
OS_LIKE="${ID_LIKE:-}"

case " $OS_ID $OS_LIKE " in
    *" ubuntu "*|*" debian "*) ;;
    *) die "Unsupported distribution: ${PRETTY_NAME:-$OS_ID}. Only Ubuntu and Debian are supported." ;;
esac

command -v apt-get >/dev/null 2>&1 || die "apt-get was not found."

PACKAGES=()
while IFS='|' read -r package purpose || [[ -n "${package:-}" ]]; do
    package="${package%%#*}"
    package="${package//[[:space:]]/}"
    [[ -z "$package" ]] && continue
    [[ "$package" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || die "Invalid package name in dependencies.txt: $package"
    PACKAGES+=("$package")
done < "$MANIFEST"

(("${#PACKAGES[@]}" > 0)) || die "No dependencies found in $MANIFEST"

log "Detected: ${PRETTY_NAME:-$OS_ID}"
log "Dependencies defined: ${#PACKAGES[@]}"
log "Updating APT package indexes..."
export DEBIAN_FRONTEND=noninteractive
apt-get update

available_packages=()
unavailable_packages=()
missing_packages=()

# Avoid piping apt-cache into an early-exiting reader under pipefail.
# Capture each policy result first, then parse the complete file.
POLICY_FILE="$(mktemp)"
trap 'rm -f "$POLICY_FILE"' EXIT

for package in "${PACKAGES[@]}"; do
    if ! apt-cache policy "$package" >"$POLICY_FILE" 2>/dev/null; then
        candidate=""
    else
        candidate="$(awk '/Candidate:/ { value=$2 } END { print value }' "$POLICY_FILE")"
    fi
    if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
        available_packages+=("$package")
        status="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)"
        if [[ "$status" != "install ok installed" ]]; then
            missing_packages+=("$package")
        fi
    else
        unavailable_packages+=("$package")
    fi
done

log "Available in configured APT repositories: ${#available_packages[@]}"
log "Dependencies missing: ${#missing_packages[@]}"
log "Dependencies unavailable: ${#unavailable_packages[@]}"

if (("${#unavailable_packages[@]}" > 0)); then
    warn "These required packages have no APT candidate in the configured repositories:"
    printf '  - %s\n' "${unavailable_packages[@]}" >&2
fi

if (("${#missing_packages[@]}" > 0)); then
    log "Packages to install:"
    printf '  - %s\n' "${missing_packages[@]}"
fi

if (("${#unavailable_packages[@]}" > 0)); then
    if [[ "$CHECK_ONLY" == true ]]; then
        die "Dependency check failed: enable the repositories containing the unavailable packages or correct dependencies.txt."
    fi
    die "Cannot install all dependencies because some packages are unavailable. No partial install was started."
fi

if [[ "$CHECK_ONLY" == true ]]; then
    if (("${#missing_packages[@]}" > 0)); then
        warn "Dependency check failed. Run 'sudo bash ${SCRIPT_NAME}' to install missing packages."
        exit 1
    fi
    log "All HostScripts dependencies are installed."
    exit 0
fi

if (("${#missing_packages[@]}" == 0)); then
    log "All HostScripts dependencies are already installed."
    exit 0
fi

log "Installing missing dependencies..."
apt-get install -y --no-install-recommends "${missing_packages[@]}"

log "Verifying installation..."
failed=()
for package in "${missing_packages[@]}"; do
    status="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)"
    [[ "$status" == "install ok installed" ]] || failed+=("$package")
done

if (("${#failed[@]}" > 0)); then
    printf '  - %s\n' "${failed[@]}" >&2
    die "Some dependencies could not be verified."
fi

log "All HostScripts dependencies are installed successfully."
