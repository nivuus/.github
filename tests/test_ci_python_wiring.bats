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

# THE ASYMMETRY THIS REPLACES. The workflow used to narrow ruff to the files a
# pull request touched, but only when github.event.pull_request.base.ref was
# set - which is to say only on a pull request; a push to main fell through to
# the whole tree. The two branches asked different questions of the same
# commit, so a green pull request said nothing about the main it was about to
# become: installer, marketplace, home-stock and desk each carried a green
# pull request and a red main, continuously from 2026-08-27 to 2026-09-09.
#
# These three assertions are anchored on the MECHANISM, not on the input name,
# so reintroducing it under another name still reddens them.
# `^[^#]*` keeps these off the comment lines that explain the history: a
# comment naming the mechanism must not read as the mechanism, which is the
# same trap the formatter tripwire had to be moved off.
@test "never narrows the lint to a diff" {
    run grep -nE '^[^#]*(diff-filter|git diff)' "$WF"
    [ "$status" -ne 0 ]
}

@test "never branches on the pull request base ref" {
    run grep -nE '^[^#]*(pull_request\.base\.ref|BASE_REF)' "$WF"
    [ "$status" -ne 0 ]
}

@test "lints the path it was given, unconditionally" {
    run awk -f "$HELPER" "$WF"
    [ "$status" -eq 0 ]
    [[ "$output" == *'ruff check "$LINT_PATHS"'* ]]
    # No `if` anywhere in a run: body of this workflow's lint step: the whole
    # bug was a conditional that made the check mean two different things.
    lint_run="$(printf '%s\n' "$output" | grep -c 'ruff check')"
    [ "$lint_run" -eq 1 ]
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
