#!/usr/bin/env bash
# Check that every commit of a Dependabot pull request is still Dependabot's.
#
# Reads the output of `gh api --paginate repos/OWNER/REPO/pulls/N/commits` on
# stdin: one JSON array per page, concatenated (the endpoint stops at 250
# commits, far beyond any branch Dependabot writes). A commit counts as
# Dependabot's only when all three hold:
#   - author.login is dependabot[bot]       (the GitHub account behind the author);
#   - committer.login is web-flow           (GitHub itself wrote the commit);
#   - commit.verification.verified is true  (and GitHub signed it).
#
# dependabot/fetch-metadata (v3) refuses a pull request whose FIRST commit
# fails the author or the signature check, and fails its step when it does. This
# check is a strict superset of that: every commit, plus the committer, which
# closes a human-signed commit merely claiming Dependabot as its author. So a
# branch passing here is never refused by fetch-metadata, and a branch rewritten
# by a human (`gh pr update-branch --rebase`, a fix commit pushed on top) is
# reported as needing review instead of turning the job red.
#
# Usage: dependabot-commits.sh < commits.json
# Exit 0: every commit is Dependabot's; the metadata may be trusted.
# Exit 3: at least one commit is not; the pull request needs human review.
# Exit 1: invalid input (unparsable JSON, not commit arrays, no commit).
set -uo pipefail

readonly DEPENDABOT_LOGIN="dependabot[bot]"
readonly GITHUB_COMMITTER_LOGIN="web-flow"

# Prints the reason a commit is not Dependabot's, or nothing when it is.
foreign_reason() {
    local author="$1" committer="$2" verified="$3"
    if [ "$author" != "$DEPENDABOT_LOGIN" ]; then
        printf 'authored by %s' "${author:-an unknown account}"
    elif [ "$committer" != "$GITHUB_COMMITTER_LOGIN" ]; then
        printf 'committed by %s' "${committer:-an unknown account}"
    elif [ "$verified" != "true" ]; then
        printf 'signature not verified'
    fi
}

main() {
    local rows
    # -s gathers the pages; each must be an array of commit objects.
    if ! rows="$(jq -rs '
            .[]
            | if type == "array" then .[] else error("expected an array of commits") end
            | if type == "object" and has("sha") then . else error("expected a commit") end
            | [.sha[0:12],
               (.author.login // ""),
               (.committer.login // ""),
               (.commit.verification.verified // false | tostring)]
            | join("\u001f")')"; then
        printf 'fatal: stdin is not the pull request commits array\n' >&2
        return 1
    fi
    if [ -z "$rows" ]; then
        printf 'fatal: no commit to check\n' >&2
        return 1
    fi

    local sha author committer verified reason verdict=0
    while IFS=$'\x1f' read -r sha author committer verified; do
        reason="$(foreign_reason "$author" "$committer" "$verified")"
        if [ -n "$reason" ]; then
            printf 'foreign    %s: %s\n' "$sha" "$reason"
            verdict=3
        else
            printf 'dependabot %s\n' "$sha"
        fi
    done <<< "$rows"

    return "$verdict"
}

main "$@"
