#!/usr/bin/env bash
# Decide whether a Dependabot pull request may be merged without a human.
#
# Reads the `updated-dependencies-json` output of dependabot/fetch-metadata on
# stdin: one object per updated dependency, each carrying its own updateType
# and prevVersion. Every dependency is judged, and the strictest one decides:
# a grouped pull request that bumps nine patches and one major waits for a
# human. fetch-metadata's scalar outputs cannot be used for this - its
# previous-version is the FIRST dependency's only, so a grouped pull request
# would be judged on whichever dependency happened to come first.
#
# Rules, per dependency:
#   - its update type must be one of ALLOWED_UPDATE_TYPES
#     (default "semver-patch semver-minor"; majors are never in the default);
#   - when its previous version is 0.x, only semver-patch is accepted: below
#     1.0 a minor bump is allowed to break the API (str0m 0.21 -> 0.24 did);
#   - an unknown update type or previous version is never guessed at.
#
# Usage: dependabot-decision.sh < updated-dependencies.json
# Exit 0: every dependency qualifies; auto-merge may be enabled.
# Exit 3: at least one dependency needs human review.
# Exit 1: invalid input (unparsable JSON, no dependency, unknown allowed type).
set -uo pipefail

readonly KNOWN_TYPES="semver-patch semver-minor semver-major"

is_allowed() {
    local type="$1" allowed
    for allowed in $ALLOWED; do
        [ "$type" = "$allowed" ] && return 0
    done
    return 1
}

# Prints the reason a dependency needs review, or nothing when it qualifies.
review_reason() {
    local type="$1" previous="$2" major
    if [ -z "$type" ]; then
        printf 'unknown update type'
        return
    fi
    if ! is_allowed "$type"; then
        printf '%s is not in the allowed update types' "$type"
        return
    fi
    if [ -z "$previous" ]; then
        printf 'unknown previous version'
        return
    fi
    major="${previous#v}"
    major="${major%%.*}"
    if [ "$major" = "0" ] && [ "$type" != "semver-patch" ]; then
        printf '%s on a 0.x version, where only patches are safe' "$type"
    fi
}

main() {
    ALLOWED="$(printf '%s' "${ALLOWED_UPDATE_TYPES:-semver-patch semver-minor}" | tr ',' ' ')"
    local type
    for type in $ALLOWED; do
        case " $KNOWN_TYPES " in
            *" $type "*) ;;
            *)
                printf 'fatal: unknown update type in ALLOWED_UPDATE_TYPES: %s (expected one of: %s)\n' \
                    "$type" "$KNOWN_TYPES" >&2
                return 1
                ;;
        esac
    done

    local rows
    if ! rows="$(jq -r '
            if type == "array" then .[] else error("expected an array") end
            | [.dependencyName // "?",
               ((.updateType // "") | sub("^version-update:"; "")),
               (.prevVersion // "")]
            | join("\u001f")')"; then
        printf 'fatal: stdin is not the updated-dependencies-json array\n' >&2
        return 1
    fi
    if [ -z "$rows" ]; then
        printf 'fatal: no updated dependency to judge\n' >&2
        return 1
    fi

    # A non-whitespace separator: with a tab, read would merge the empty
    # field of an unknown update type into its neighbour.
    local name previous reason verdict=0
    while IFS=$'\x1f' read -r name type previous; do
        reason="$(review_reason "$type" "$previous")"
        if [ -n "$reason" ]; then
            printf 'review  %s %s: %s\n' "$name" "${previous:-?}" "$reason"
            verdict=3
        else
            printf 'merge   %s %s: %s\n' "$name" "$previous" "$type"
        fi
    done <<< "$rows"

    return "$verdict"
}

main "$@"
