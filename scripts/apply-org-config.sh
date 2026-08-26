#!/usr/bin/env bash
# Apply the shared Nivuus server-side configuration to one or more repos.
# Usage: apply-org-config.sh [--dry-run] <owner/repo>...
set -uo pipefail

GH_BIN="${GH_BIN:-gh}"
DRY_RUN=0

# Required status check contexts. A reusable workflow is reported as
# "<caller job id> / <called job name>", not just the job id.
readonly CHECK_POLICY="policy / Coding rules"
readonly CHECK_SECURITY="security / Secrets and dependencies"

run_gh() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'DRY-RUN: %s %s\n' "$GH_BIN" "$*"
        return 0
    fi
    "$GH_BIN" "$@"
}

visibility_of() {
    local repo="$1"
    export GH_VISIBILITY_QUERY="api repos/${repo} --jq .visibility"
    "$GH_BIN" api "repos/${repo}" --jq .visibility
}

apply_merge_strategy() {
    local repo="$1"
    run_gh api -X PATCH "repos/${repo}" \
        -F delete_branch_on_merge=true \
        -F allow_squash_merge=true \
        -F allow_merge_commit=false \
        -F allow_rebase_merge=false
}

apply_secret_scanning() {
    local repo="$1"
    run_gh api -X PATCH "repos/${repo}" \
        -f 'security_and_analysis[secret_scanning][status]=enabled' \
        -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
}

apply_private_reporting() {
    local repo="$1"
    run_gh api -X PUT "repos/${repo}/private-vulnerability-reporting"
}

apply_dependabot() {
    local repo="$1"
    run_gh api -X PUT "repos/${repo}/vulnerability-alerts"
    run_gh api -X PUT "repos/${repo}/automated-security-fixes"
}

apply_branch_protection() {
    local repo="$1"
    local payload
    payload=$(cat <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["${CHECK_POLICY}", "${CHECK_SECURITY}"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
)
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'DRY-RUN: %s api -X PUT repos/%s/branches/main/protection\n' "$GH_BIN" "$repo"
        return 0
    fi
    printf '%s' "$payload" \
        | "$GH_BIN" api -X PUT "repos/${repo}/branches/main/protection" --input -
}

apply_repo() {
    local repo="$1" vis rc=0

    printf '\n== %s ==\n' "$repo"

    if ! vis="$(visibility_of "$repo")"; then
        printf 'ERROR: %s: visibility lookup failed; repository left unconfigured.\n' "$repo"
        return 1
    fi

    apply_merge_strategy "$repo" || rc=1
    apply_dependabot "$repo" || rc=1

    if [ "$vis" = "public" ]; then
        apply_secret_scanning "$repo" || rc=1
        apply_private_reporting "$repo" || rc=1
        apply_branch_protection "$repo" || rc=1
    else
        printf 'WARNING: %s is %s. Branch protection, secret scanning and private vulnerability reporting need a paid plan; skipping.\n' \
            "$repo" "$vis"
    fi

    return "$rc"
}

main() {
    local rc=0 repo
    local -a repos=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1; shift ;;
            --*) printf 'Unknown option: %s\n' "$1"; return 2 ;;
            *) repos+=("$1"); shift ;;
        esac
    done

    if [ "${#repos[@]}" -eq 0 ]; then
        printf 'Usage: apply-org-config.sh [--dry-run] <owner/repo>...\n'
        return 2
    fi

    for repo in "${repos[@]}"; do
        apply_repo "$repo" || rc=1
    done

    return "$rc"
}

main "$@"
