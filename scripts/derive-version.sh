#!/usr/bin/env bash
# Derive the next semantic version from the conventional commits since the
# last version tag.
#
# The suite already enforces conventional English subjects on every pull
# request title (check-commits.sh), and protected branches merge by squash,
# so the merge commit subject IS a conventional commit. Deriving the version
# from them turns a rule that was pure overhead into the release engine.
#
# Usage: derive-version.sh
# Exit 0: the next version is on stdout.
# Exit 3: nothing releasable since the last tag; stdout is empty.
set -uo pipefail

readonly SCOPE='(\([a-z0-9._/-]+\))?'
readonly FEAT_RE="^feat${SCOPE}: "
readonly PATCH_RE="^(fix|perf|refactor)${SCOPE}: "
readonly BREAKING_RE="^[a-z]+${SCOPE}!: "

main() {
    # Refuse to run outside a git repository
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        printf 'fatal: not a git repository\n' >&2
        return 1
    fi

    local last
    last="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"

    if [ -z "$last" ]; then
        # Refuse a shallow clone where tags may not have been fetched
        if git rev-parse --is-shallow-repository | grep -q '^true$'; then
            printf 'fatal: shallow clone detected; full history or fetched tags required for version derivation\n' >&2
            return 1
        fi
        printf '%s\n' "${INITIAL_VERSION:-1.0.0}"
        return 0
    fi

    local major minor patch
    IFS=. read -r major minor patch <<< "${last#v}"

    local bump="none" subject
    while IFS= read -r subject; do
        [ -n "$subject" ] || continue
        if [[ "$subject" =~ $BREAKING_RE ]]; then
            bump="major"
            break
        fi
        if [[ "$subject" =~ $FEAT_RE ]] && [ "$bump" != major ]; then
            bump="minor"
        fi
        if [[ "$subject" =~ $PATCH_RE ]] && [ "$bump" = none ]; then
            bump="patch"
        fi
    done < <(git log --no-merges --format='%s' "${last}..HEAD")

    # A breaking change may also be declared in the body rather than with the
    # bang marker; the footer is the form the Conventional Commits spec makes
    # normative, so it cannot be treated as a lesser signal.
    if [ "$bump" != major ] \
        && git log --no-merges --format='%b' "${last}..HEAD" \
            | grep -q '^BREAKING CHANGE:'; then
        bump="major"
    fi

    case "$bump" in
        major) printf '%d.0.0\n' "$((major + 1))" ;;
        minor) printf '%d.%d.0\n' "$major" "$((minor + 1))" ;;
        patch) printf '%d.%d.%d\n' "$major" "$minor" "$((patch + 1))" ;;
        *)     return 3 ;;
    esac
}

main "$@"
