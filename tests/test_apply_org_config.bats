#!/usr/bin/env bats

setup() {
    SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"
    WORK="$(mktemp -d)"
    cd "$WORK" || return 1

    # A gh double: logs its arguments, answers visibility queries.
    cat > gh <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
if [ "$*" = "${GH_VISIBILITY_QUERY}" ]; then
    printf '%s\n' "${GH_VISIBILITY:-public}"
fi
exit 0
STUB
    chmod +x gh
    export GH_BIN="$WORK/gh"
    export GH_LOG="$WORK/calls.log"
    : > "$GH_LOG"
}

teardown() {
    [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

@test "requires at least one repository" {
    run "$SCRIPTS/apply-org-config.sh"
    [ "$status" -ne 0 ]
}

@test "dry-run performs no write call" {
    run "$SCRIPTS/apply-org-config.sh" --dry-run nivuus/shell
    [ "$status" -eq 0 ]
    run grep -c "PUT\|PATCH" "$GH_LOG"
    [ "$output" = "0" ]
}

@test "sets the merge strategy on a public repo" {
    export GH_VISIBILITY=public
    run "$SCRIPTS/apply-org-config.sh" nivuus/shell
    [ "$status" -eq 0 ]
    grep -q "delete_branch_on_merge=true" "$GH_LOG"
    grep -q "allow_squash_merge=true" "$GH_LOG"
    grep -q "allow_merge_commit=false" "$GH_LOG"
}

@test "protects the main branch of a public repo" {
    export GH_VISIBILITY=public
    run "$SCRIPTS/apply-org-config.sh" nivuus/shell
    [ "$status" -eq 0 ]
    grep -q "branches/main/protection" "$GH_LOG"
}

@test "skips branch protection on a private repo" {
    export GH_VISIBILITY=private
    run "$SCRIPTS/apply-org-config.sh" nivuus/desk
    [ "$status" -eq 0 ]
    run grep -c "branches/main/protection" "$GH_LOG"
    [ "$output" = "0" ]
}

@test "warns when it skips a private repo" {
    export GH_VISIBILITY=private
    run "$SCRIPTS/apply-org-config.sh" nivuus/desk
    [[ "$output" == *"WARNING"* ]]
}

@test "enables dependabot alerts on every repo" {
    export GH_VISIBILITY=private
    run "$SCRIPTS/apply-org-config.sh" nivuus/desk
    [ "$status" -eq 0 ]
    grep -q "vulnerability-alerts" "$GH_LOG"
}

@test "handles several repositories in one run" {
    export GH_VISIBILITY=public
    run "$SCRIPTS/apply-org-config.sh" nivuus/shell nivuus/mqtt
    [ "$status" -eq 0 ]
    grep -q "nivuus/shell" "$GH_LOG"
    grep -q "nivuus/mqtt" "$GH_LOG"
}

@test "enables private vulnerability reporting on a public repo" {
    export GH_VISIBILITY=public
    run "$SCRIPTS/apply-org-config.sh" nivuus/shell
    [ "$status" -eq 0 ]
    grep -q "private-vulnerability-reporting" "$GH_LOG"
}

@test "propagates a failed visibility lookup instead of guessing" {
    cat > gh <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
if [ "$*" = "${GH_VISIBILITY_QUERY}" ]; then
    exit 1
fi
exit 0
STUB
    chmod +x gh
    run "$SCRIPTS/apply-org-config.sh" nivuus/shell
    [ "$status" -ne 0 ]
    run grep -c "branches/main/protection" "$GH_LOG"
    [ "$output" = "0" ]
}

@test "dry-run after the repository argument still performs no write call" {
    run "$SCRIPTS/apply-org-config.sh" nivuus/shell --dry-run
    [ "$status" -eq 0 ]
    run grep -c "PUT\|PATCH" "$GH_LOG"
    [ "$output" = "0" ]
}

@test "rejects an unknown option after a repository name" {
    run "$SCRIPTS/apply-org-config.sh" nivuus/shell --bogus
    [ "$status" -eq 2 ]
}
