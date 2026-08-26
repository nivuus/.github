#!/usr/bin/env bash
# Enforce English in code: identifiers, comments and docstrings.
# Reads one path per line on stdin. Exits 1 on any violation.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENGINE="${SELF_DIR}/lib/english.awk"
readonly WORDS="${SELF_DIR}/lib/french-words.txt"

# shellcheck source=lib/paths.sh
source "${SELF_DIR}/lib/paths.sh"

main() {
    local path lang out failed=0

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ -f "$path" ] || continue
        is_generated_path "$path" && continue
        is_test_path "$path" && continue
        lang="$(dialect_of "$path")" || continue

        if ! out="$(gawk -v lang="$lang" -v words="$WORDS" -f "$ENGINE" "$path")"; then
            printf '%s\n' "$out" | sed "s|^|${path}:|"
            failed=1
        fi
    done

    if [ "$failed" -eq 1 ]; then
        printf '\nCode must be written in English. User-facing strings stay in French.\n'
        printf 'Add "policy: allow-fr" at the end of a line to allow a legitimate exception.\n'
    fi

    return "$failed"
}

main "$@"
