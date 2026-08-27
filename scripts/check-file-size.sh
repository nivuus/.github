#!/usr/bin/env bash
# Enforce the maximum source file length.
# Reads one path per line on stdin. Exits 1 if any file exceeds the limit.
set -uo pipefail

MAX_LINES="${MAX_LINES:-500}"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/paths.sh
source "${SELF_DIR}/lib/paths.sh"

is_checked() {
    local path="$1"
    is_generated_path "$path" && return 1
    is_test_path "$path" && return 1
    dialect_of "$path" > /dev/null || return 1
    return 0
}

main() {
    local path lines failed=0

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ -f "$path" ] || continue
        is_checked "$path" || continue
        grep -q 'policy: allow-long-file' "$path" && continue

        lines=$(wc -l < "$path")
        if [ "$lines" -gt "$MAX_LINES" ]; then
            printf '%s: %d lines (max %d) — split this file into focused units\n' \
                "$path" "$lines" "$MAX_LINES"
            printf '  Put "policy: allow-long-file" in the file, with the reason, for a deliberate exception.\n'
            failed=1
        fi
    done

    return "$failed"
}

main "$@"
