#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/ci-shell.yml"
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

@test "passes github expressions through env, never into run blocks" {
    run grep -nE '^ +run:.*\$\{\{' "$WF"
    [ "$status" -ne 0 ]
}
