#!/usr/bin/env bash
# Enforce Conventional Commits, with English subjects.
# Usage: check-commits.sh <base_ref> <head_ref>
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENGINE="${SELF_DIR}/lib/english.awk"
readonly WORDS="${SELF_DIR}/lib/french-words.txt"

readonly TYPES='feat|fix|chore|docs|refactor|test|ci|perf|build|style|revert'
readonly SUBJECT_RE="^(${TYPES})(\([a-z0-9._/-]+\))?!?: .+"

subject_is_french() {
    # The engine exits 1 when it flags the line, 0 otherwise. Test the
    # pipeline directly in the if so no intermediate $? read is needed,
    # then invert it: engine success (English) means this is not French.
    if printf '%s\n' "$1" \
        | gawk -v lang=sh -v words="$WORDS" -f "$ENGINE" > /dev/null; then
        return 1
    fi
    return 0
}

check_subject() {
    local subject="$1"

    if ! [[ "$subject" =~ $SUBJECT_RE ]]; then
        printf 'Not a conventional commit: %s\n' "$subject"
        return 1
    fi

    if subject_is_french "${subject#*: }"; then
        printf 'Commit subject must be in English: %s\n' "$subject"
        return 1
    fi

    return 0
}

main() {
    if [ "${1:-}" = "--subject" ]; then
        shift
        check_subject "${1:-}" && return 0
        return 1
    fi

    local base="${1:-origin/main}" head="${2:-HEAD}"
    local subject failed=0

    while IFS= read -r subject; do
        [ -n "$subject" ] || continue
        check_subject "$subject" || failed=1
    done < <(git log --no-merges --format='%s' "${base}..${head}")

    if [ "$failed" -eq 1 ]; then
        printf '\nExpected format: <type>(<scope>)!: <english subject>\n'
        printf 'Allowed types: %s\n' "${TYPES//|/, }"
    fi

    return "$failed"
}

main "$@"
