#!/usr/bin/env bash
set -Eeuo pipefail

TARGET="${1:-/}"
if [[ ! -d "$TARGET" ]]; then
    printf 'Error: directory does not exist: %s\n' "$TARGET" >&2
    printf 'Usage: %s [directory]\n' "$0" >&2
    exit 2
fi

printf '\n=== Filesystem usage ===\n'
df -hT "$TARGET"

printf '\n=== Inode usage ===\n'
df -ih "$TARGET"

printf '\n=== Largest top-level directories under %s ===\n' "$TARGET"
if command -v du >/dev/null 2>&1; then
    du -xhd1 "$TARGET" 2>/dev/null | sort -h | tail -n 15
fi

printf '\n=== Largest files under %s (top 20) ===\n' "$TARGET"
find "$TARGET" -xdev -type f -printf '%s\t%p\n' 2>/dev/null |
    sort -nr |
    head -n 20 |
    awk -F '\t' '{ size=$1; $1=""; sub(/^\t/, ""); printf "%8.2f MiB  %s\n", size/1048576, $0 }'
