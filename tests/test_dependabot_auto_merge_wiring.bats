#!/usr/bin/env bats

load helpers/run_blocks

# Action references are matched without their version on purpose: a test
# pinning setup-node@v4 broke on every Dependabot bump, which is exactly the
# kind of pull request this workflow exists to merge.

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/dependabot-auto-merge.yml"
    HELPER="${BATS_TEST_DIRNAME}/helpers/extract_run_blocks.awk"
}

@test "dependabot auto-merge workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

# github.actor is whoever caused the run - a human re-running it included.
# The pull request author is whose changes these are.
@test "runs only on pull requests authored by dependabot" {
    grep -qF "if: github.event.pull_request.user.login == 'dependabot[bot]'" "$WF"
    run grep -qE "if:.*github\.actor" "$WF"
    [ "$status" -ne 0 ]
}

@test "reads the update metadata with dependabot/fetch-metadata" {
    grep -qE "uses: dependabot/fetch-metadata@" "$WF"
}

# The scalar previous-version output describes the first dependency only; a
# grouped pull request must be judged dependency by dependency.
@test "judges every dependency from the full json, not the scalar outputs" {
    grep -q "steps.metadata.outputs.updated-dependencies-json" "$WF"
    grep -q "dependabot-decision.sh" "$WF"
    run grep -qE "outputs\.(update-type|previous-version)" "$WF"
    [ "$status" -ne 0 ]
}

@test "majors are not auto-merged by default" {
    grep -qE 'default: "semver-patch semver-minor"$' "$WF"
}

@test "only a needs-review verdict is a clean skip; other failures fail the job" {
    grep -qE '^ +3\)' "$WF"
    grep -qE '^ +\*\) exit "\$status"' "$WF"
}

@test "enables auto-merge rather than merging directly" {
    grep -qE 'run: gh pr merge --auto --squash "\$PR_URL"' "$WF"
}

# A swallowed failure here would hide a repository with auto-merge disabled.
@test "never swallows a failed merge" {
    run grep -qE "continue-on-error|\|\| true" "$WF"
    [ "$status" -ne 0 ]
}

@test "the job holds exactly the write permissions auto-merge needs" {
    grep -q "contents: write" "$WF"
    grep -q "pull-requests: write" "$WF"
}

@test "takes the decision script from the socle" {
    grep -q "repository: nivuus/.github" "$WF"
    grep -q 'ref: ${{ inputs.socle-ref }}' "$WF"
}

# The job holds a write token: code from the pull request must never run.
@test "never checks out the pull request itself" {
    [ "$(grep -c "uses: actions/checkout@" "$WF")" -eq 1 ]
}

@test "passes github expressions through env, never into run blocks (including multi-line)" {
    [ -f "$HELPER" ]
    run leaked_expressions "$HELPER" "$WF"
    [ "$status" -eq 1 ]
}
