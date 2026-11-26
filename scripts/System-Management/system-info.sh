#!/usr/bin/env bash
set -Eeuo pipefail

section() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$1"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
fi

section "Operating System"
printf 'Hostname:       %s\n' "$(hostname 2>/dev/null || echo unknown)"
printf 'Distribution:   %s\n' "${PRETTY_NAME:-Unknown}"
printf 'Kernel:         %s\n' "$(uname -srmo)"
printf 'Uptime:         %s\n' "$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo unknown)"
printf 'Architecture:   %s\n' "$(uname -m)"

section "CPU"
if command_exists lscpu; then
    lscpu | grep -E '^(Model name|CPU\(s\)|Socket\(s\)|Core\(s\) per socket|Thread\(s\) per core):' || true
else
    printf 'Processors:     %s\n' "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo unknown)"
fi

section "Memory"
if command_exists free; then
    free -h
else
    echo "free command not found."
fi

section "Storage"
if command_exists df; then
    df -hT -x tmpfs -x devtmpfs
else
    echo "df command not found."
fi

section "Network"
if command_exists ip; then
    ip -brief address 2>/dev/null || ip address
    printf '\nDefault routes:\n'
    ip route show default 2>/dev/null || true
else
    echo "ip command not found."
fi

section "Virtualization"
if command_exists systemd-detect-virt; then
    systemd-detect-virt || true
else
    echo "systemd-detect-virt command not found."
fi

section "Load Average"
cat /proc/loadavg 2>/dev/null || echo "Load average unavailable."

section "Top Processes"
if command_exists ps; then
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 11
fi
