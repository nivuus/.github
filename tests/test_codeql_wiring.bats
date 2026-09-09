#!/usr/bin/env bats

load helpers/run_blocks

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/codeql.yml"
    HELPER="${BATS_TEST_DIRNAME}/helpers/extract_run_blocks.awk"
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
