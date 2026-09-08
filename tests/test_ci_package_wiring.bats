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

# Checking these two properties independently lets either drift without the
# other: a step could check the socle out to .nivuus-socle while calling
# check-idempotence.sh from anywhere, or vice versa. Only the joined path
# proves the script that actually runs is the one from the socle checkout.
@test "checks out the socle and invokes its script from that checkout" {
    grep -q "repository: nivuus/.github" "$WF"
    grep -q "path: .nivuus-socle" "$WF"
    grep -qF ".nivuus-socle/scripts/check-idempotence.sh" "$WF"
}

@test "installs what the harness imports" {
    grep -q "pyyaml" "$WF"
}

# The script (task 4) reads the answers file from NIVUUS_ANSWERS_FILE, not
# from a flag - console cannot install without a windows_iso answer.
@test "passes the answers file via NIVUUS_ANSWERS_FILE" {
    grep -q "NIVUUS_ANSWERS_FILE" "$WF"
}

# A single-line anchor (^ +run:.*\$\{\{) is blind the moment a run: value
# moves into a `run: |` block: the expression lands on a following line the
# regex never inspects. extract_run_blocks.awk walks every run: step
# (single-line value or multi-line block, by indentation) and prints its
# full body, so the expression is caught wherever inside a run: it lands.
@test "passes github expressions through env, never into run blocks (including multi-line)" {
    run bash -c "awk -f '${BATS_TEST_DIRNAME}/helpers/extract_run_blocks.awk' '$WF' | grep -F '\${{'"
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
