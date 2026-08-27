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

# A pyproject.toml holding only [tool.ruff] is not an installable package;
# pip install . would fail hard on it.
@test "installs only when pyproject describes a package" {
    grep -q "build-system|project" "$WF"
}

@test "restricts ruff to changed files by default" {
    grep -q "changed-only:" "$WF"
    grep -q "diff-filter=ACMR" "$WF"
}

# Without full history the diff has no base and the step fails.
@test "fetches full history so the diff has a base" {
    grep -q "fetch-depth: 0" "$WF"
}

@test "skips when no Python file changed" {
    grep -q "No Python file changed" "$WF"
}

# Exit 5 is "no tests collected", not a failure. Without this, every
# repository lacking a pytest suite goes red.
@test "treats an empty pytest collection as success" {
    grep -q "eq 5" "$WF"
}

@test "still fails when tests actually fail" {
    grep -q 'exit "$status"' "$WF"
}
