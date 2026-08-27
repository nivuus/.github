#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/ci-python.yml"
}

@test "ci-python workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "exposes an overridable python version" {
    grep -q "python-version:" "$WF"
}

@test "exposes overridable test and lint paths" {
    grep -q "test-paths:" "$WF"
    grep -q "lint-paths:" "$WF"
}

@test "runs ruff and pytest" {
    grep -q "ruff" "$WF"
    grep -q "pytest" "$WF"
}

# installer has 40 Python files and no manifest at all; a hard dependency
# install would fail there.
@test "installs dependencies only when a manifest exists" {
    grep -q "requirements.txt" "$WF"
    grep -q "pyproject.toml" "$WF"
}

# marketplace has Python files but no tests directory.
@test "skips cleanly when there is nothing to test" {
    grep -qi "skipping" "$WF"
}

@test "passes github expressions through env, never into run blocks" {
    run grep -nE '^ +run:.*\$\{\{' "$WF"
    [ "$status" -ne 0 ]
}
