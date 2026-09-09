#!/usr/bin/env bats

load helpers/run_blocks

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/ci-shell.yml"
    HELPER="${BATS_TEST_DIRNAME}/helpers/extract_run_blocks.awk"
}

@test "ci-shell workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "exposes overridable test directories" {
    grep -q "test-dirs:" "$WF"
}

@test "exposes an overridable shellcheck root" {
    grep -q "shellcheck-paths:" "$WF"
}

@test "runs shellcheck and bats" {
    grep -q "shellcheck" "$WF"
    grep -q "bats" "$WF"
}

@test "installs zsh, required by the shell test suite" {
    grep -q "zsh" "$WF"
}

# A single-line anchor (^ +run:.*\$\{\{) is blind the moment a run: value
# moves into a `run: |` block: the expression lands on a following line the
# regex never inspects. extract_run_blocks.awk walks every run: step
# (single-line value or multi-line block, by indentation) and prints its
# full body, so the expression is caught wherever inside a run: it lands.
@test "passes github expressions through env, never into run blocks (including multi-line)" {
    [ -f "$HELPER" ]
    run leaked_expressions "$HELPER" "$WF"
    # 1 = the extractor ran fine and grep found nothing. 0 would mean a
    # leak; 2 would mean the extractor itself is missing or broken - both
    # must fail this test, never read as "clean".
    [ "$status" -eq 1 ]
}

# shellcheck cannot read zsh, so without this nothing validates the syntax of
# a zsh project's own sources.
@test "offers an optional zsh syntax check" {
    grep -q "zsh-syntax-paths:" "$WF"
    grep -q "zsh -n" "$WF"
}
