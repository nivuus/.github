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
        grep -q 'policy: allow-fr-file' "$path" && continue
        lang="$(dialect_of "$path")" || continue

        if ! out="$(gawk -v lang="$lang" -v words="$WORDS" -f "$ENGINE" "$path")"; then
            printf '%s\n' "$out" | sed "s|^|${path}:|"
            failed=1
        fi
    done

    if [ "$failed" -eq 1 ]; then
        printf '\nCode must be written in English. A single-line French user-facing string is allowed as is.\n'
        printf 'Put "policy: allow-fr" in a comment on the offending line for a legitimate exception; it has no effect inside a string.\n'
        printf 'Put "policy: allow-fr-file" anywhere in the file to exempt it entirely, for multi-line user-facing text such as a heredoc.\n'
    fi

    return "$failed"
}

main "$@"
