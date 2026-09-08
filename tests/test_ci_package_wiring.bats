#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/ci-package.yml"
}

@test "ci-package workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "exposes an overridable package directory" {
    grep -q "package-dir:" "$WF"
}

@test "exposes an overridable answers file" {
    grep -q "answers-file:" "$WF"
}

@test "checks out the socle to reach its scripts" {
    grep -q "repository: nivuus/.github" "$WF"
    grep -q ".nivuus-socle" "$WF"
}

@test "runs the idempotence proof" {
    grep -q "check-idempotence.sh" "$WF"
}

@test "installs what the harness imports" {
    grep -q "pyyaml" "$WF"
}

# The script (task 4) reads the answers file from NIVUUS_ANSWERS_FILE, not
# from a flag - console cannot install without a windows_iso answer.
@test "passes the answers file via NIVUUS_ANSWERS_FILE" {
    grep -q "NIVUUS_ANSWERS_FILE" "$WF"
}

@test "passes github expressions through env, never into run blocks" {
    run grep -nE '^ +run:.*\$\{\{' "$WF"
    [ "$status" -ne 0 ]
}

# The dependency clones the script performs need git and network access,
# which a restrictive checkout could interfere with. Guard against that
# regression by never seeing a persist-credentials: false or similar
# submodule/sparse restriction slip in for the caller checkout.
@test "does not restrict the caller checkout in a way that could break cloning dependencies" {
    run grep -nE 'persist-credentials: *false' "$WF"
    [ "$status" -ne 0 ]
}
