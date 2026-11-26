#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_URL="https://get.docker.com"
TMP_SCRIPT=""

cleanup() {
    [[ -n "${TMP_SCRIPT}" && -f "${TMP_SCRIPT}" ]] && rm -f "${TMP_SCRIPT}"
}
trap cleanup EXIT

info() { printf '\n\033[1;36m[INFO]\033[0m %s\n' "$*"; }
success() { printf '\n\033[1;32m[SUCCESS]\033[0m %s\n' "$*"; }
error() { printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

info "Checking whether Docker's official installer can run on this host..."

if [[ "$(uname -s)" != "Linux" ]]; then
    error "This installer supports Linux hosts only."
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    error "Cannot identify this Linux distribution (/etc/os-release is missing)."
    exit 1
fi

. /etc/os-release
DISTRO_ID="${ID,,}"
case "$DISTRO_ID" in
    ubuntu|debian) ;;
    *)
        error "Unsupported distribution: ${PRETTY_NAME:-$DISTRO_ID}. This HostScripts installer allows Ubuntu and Debian only."
        exit 1
        ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|aarch64|armv7l) ;;
    *)
        error "Unsupported CPU architecture: $ARCH."
        exit 1
        ;;
esac

if ! command -v curl >/dev/null 2>&1; then
    error "curl is required. Install curl and run this script again."
    exit 1
fi

if ! command -v bash >/dev/null 2>&1; then
    error "bash is required but was not found."
    exit 1
fi

if (( EUID != 0 )); then
    if ! command -v sudo >/dev/null 2>&1; then
        error "Run this script as root or install sudo first."
        exit 1
    fi
    info "Checking sudo access..."
    sudo -v
    RUN=(sudo)
else
    RUN=()
fi

if command -v docker >/dev/null 2>&1; then
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet docker; then
        success "Docker is already installed and the Docker service is running."
        docker --version
        exit 0
    fi
    info "Docker binary exists, but the Docker service is not active. The installer will be run and the service checked."
fi

info "Supported host detected: ${PRETTY_NAME:-$DISTRO_ID} ($ARCH)."
info "Downloading Docker's official installation script from $INSTALL_URL..."

TMP_SCRIPT="$(mktemp)"
if ! curl -fsSL "$INSTALL_URL" -o "$TMP_SCRIPT"; then
    error "Could not download the official Docker installation script. Check network access and try again."
    exit 1
fi

if [[ ! -s "$TMP_SCRIPT" ]] || ! head -n 1 "$TMP_SCRIPT" | grep -qE '^#!/.*(sh|bash)'; then
    error "The downloaded installer is empty or does not look like a shell script. Refusing to execute it."
    exit 1
fi

info "Running Docker's official installer. This may take several minutes..."
"${RUN[@]}" bash "$TMP_SCRIPT"

if command -v systemctl >/dev/null 2>&1; then
    info "Enabling and starting Docker..."
    "${RUN[@]}" systemctl enable --now docker
fi

if ! command -v docker >/dev/null 2>&1; then
    error "Installer finished, but the docker command was not found."
    exit 1
fi

if command -v systemctl >/dev/null 2>&1 && ! systemctl is-active --quiet docker; then
    error "Docker was installed, but the Docker service is not running."
    exit 1
fi

docker --version
success "Docker Engine installation completed and Docker is ready."
