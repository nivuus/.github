#!/usr/bin/env bats

load helpers/run_blocks

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/ci-python.yml"
    HELPER="${BATS_TEST_DIRNAME}/helpers/extract_run_blocks.awk"
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

# The formatter check was removed on 2026-09-09, and the workflow carries the
# reasoning. What it cannot carry is a guard: `ruff format --check` is one
# line, it reads as an obvious improvement, and re-adding it turns every
# repository in the suite red on merge and only on merge. This test is the
# tripwire - reintroducing it must be a deliberate change that also updates
# this expectation, not a drive-by line.
@test "does not enforce code formatting" {
    [ -f "$HELPER" ]
    # Read the run: bodies, not the file: the workflow's own comment explains
    # why the formatter is gone and names it, so a whole-file grep would trip
    # on the explanation instead of on a command.
    run awk -f "$HELPER" "$WF"
    [ "$status" -eq 0 ]
    [[ "$output" != *"ruff format"* ]]
}
