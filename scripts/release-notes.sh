#!/usr/bin/env bash
# Build the body of a GitHub release, on stdout.
#
# WHY THIS IS A SCRIPT AND NOT A `run:` BLOCK. It has one rule that is easy to
# get backwards and impossible to see in a workflow log: what it drops when the
# changelog does not fit. GitHub refuses a release body over 125000 characters
# with HTTP 422 "body is too long" - measured on nivuus/desk, whose FIRST
# release covers 1386 commits because no previous tag bounds the log. The 422
# lands AFTER the assets are built and attested, and `gh release create` makes
# the tag and the release in one call, so it costs the whole release: no tag,
# no release, nothing to retry against.
#
# The rule: keep the NEWEST entries, drop the oldest, and say how many were
# dropped. A truncated changelog missing its oldest lines is still a changelog.
# One missing its newest lines is a lie about what shipped - and that is the
# easy mistake, because `git log` prints newest first and the obvious-looking
# `tac | awk` inverts exactly this. Measured while writing it: the reversed
# version kept 1253 ancient entries on desk and silently dropped the 104 most
# recent, HEAD included. tests/test_release_notes.bats pins the direction.
set -euo pipefail

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "release-notes.sh: not inside a git repository" >&2
    exit 1
fi

# The changelog's share of the body. The rest goes to the heading, the "Pose"
# section and the truncation notice, and 10000 characters is far more than
# those need.
BUDGET="${NOTES_BUDGET:-115000}"
# `set -u` makes ${GITHUB_REPOSITORY##*/} a hard failure outside Actions,
# where the variable does not exist - which is where the tests run.
repository="${GITHUB_REPOSITORY:-}"
PACKAGE="${PACKAGE:-${repository##*/}}"

previous="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
changes="$(mktemp)"
trap 'rm -f "$changes"' EXIT

if [ -z "$previous" ]; then
    git log --no-merges --pretty=format:'- %s (%h)' > "$changes"
else
    git log "${previous}..HEAD" --no-merges --pretty=format:'- %s (%h)' > "$changes"
fi
# `git log --pretty=format:` writes no trailing newline, so the last entry
# would otherwise not be a line at all.
echo >> "$changes"

total="$(grep -c '^-' "$changes" || true)"

echo "## Changements"
echo
awk -v budget="$BUDGET" -v total="$total" '
    /^-/ {
        size = length($0) + 1
        if (bytes + size > budget) { skipped = total - kept; exit }
        bytes += size
        print
        kept++
    }
    END {
        if (skipped > 0)
            printf("\n_Et %d changement(s) plus ancien(s), omis : le corps d une release GitHub est limite a 125 000 caracteres._\n", skipped)
    }' "$changes"
echo
echo
echo "## Pose"
echo
echo '```'
echo "nivuus update ${PACKAGE}"
echo '```'
