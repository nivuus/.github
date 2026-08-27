#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/codeql.yml"
}

@test "codeql workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "takes the languages to analyse as an input" {
    grep -q "languages:" "$WF"
}

@test "runs the three codeql steps" {
    grep -q "github/codeql-action/init" "$WF"
    grep -q "github/codeql-action/autobuild" "$WF"
    grep -q "github/codeql-action/analyze" "$WF"
}

# Uploading results needs this permission; without it the run fails at the end,
# after doing all the work.
@test "grants the security-events permission" {
    grep -q "security-events: write" "$WF"
}

@test "passes github expressions through env, never into run blocks" {
    run grep -nE '^ +run:.*\$\{\{' "$WF"
    [ "$status" -ne 0 ]
}
