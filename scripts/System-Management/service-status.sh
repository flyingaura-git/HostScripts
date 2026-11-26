#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v systemctl >/dev/null 2>&1; then
    printf 'Error: systemctl is not available on this host.\n' >&2
    exit 1
fi

if (( $# == 0 )); then
    printf 'Usage: %s SERVICE [SERVICE ...]\n' "$0"
    printf 'Example: %s ssh nginx docker\n' "$0"
    printf '\nActive services (first 30):\n'
    systemctl list-units --type=service --state=active --no-pager --no-legend | head -n 30
    exit 0
fi

failed=0
for service in "$@"; do
    printf '\n=== %s ===\n' "$service"
    if systemctl status "$service" --no-pager --full; then
        :
    else
        status=$?
        printf 'Could not retrieve a successful status for %s (systemctl exit: %s).\n' "$service" "$status"
        failed=1
    fi
done
exit "$failed"
