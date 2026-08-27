#!/usr/bin/env bash
# Enforce English in code: identifiers, comments and docstrings.
# Reads one path per line on stdin. Exits 1 on any violation.
#
# Usage: check-english.sh [--added-only <base_ref> <head_ref>]
#
# Without --added-only, every line of every listed file is checked. With it,
# only lines the diff between base_ref and head_ref actually adds or modifies
# are reported: pre-existing lines in a touched file are left alone.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENGINE="${SELF_DIR}/lib/english.awk"
readonly WORDS="${SELF_DIR}/lib/french-words.txt"

# shellcheck source=lib/paths.sh
source "${SELF_DIR}/lib/paths.sh"
# shellcheck source=lib/changed-lines.sh
source "${SELF_DIR}/lib/changed-lines.sh"

main() {
    local path lang out failed=0
    local added_only=0 base_ref="" head_ref="" added

    if [ "${1:-}" = "--added-only" ]; then
        added_only=1
        base_ref="$2"
        head_ref="$3"
        shift 3
    fi

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ -f "$path" ] || continue
        is_generated_path "$path" && continue
        is_test_path "$path" && continue
        grep -q 'policy: allow-fr-file' "$path" && continue
        lang="$(dialect_of "$path")" || continue

        if ! out="$(gawk -v lang="$lang" -v words="$WORDS" -f "$ENGINE" "$path")"; then
            if [ "$added_only" -eq 1 ]; then
                added="$(added_lines "$base_ref" "$head_ref" "$path")"
                [ -n "$added" ] || continue
                out="$(printf '%s\n' "$out" | gawk -v keep="$added" '
                    BEGIN { n = split(keep, a, "\n"); for (i = 1; i <= n; i++) want[a[i]] = 1 }
                    { split($0, f, ":"); if (f[1] in want) print }
                ')"
                [ -n "$out" ] || continue
            fi
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
