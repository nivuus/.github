#!/usr/bin/env bats

load helpers/run_blocks

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/ci-rust.yml"
    HELPER="${BATS_TEST_DIRNAME}/helpers/extract_run_blocks.awk"
}

@test "ci-rust workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "exposes an overridable manifest path" {
    grep -q "manifest-path:" "$WF"
}

@test "checks formatting, lints and tests" {
    grep -q "cargo fmt" "$WF"
    grep -q "cargo clippy" "$WF"
    grep -q "cargo test" "$WF"
}

# A warning that does not fail the build is a warning nobody fixes.
@test "treats clippy warnings as errors" {
    grep -q -- "-D warnings" "$WF"
}

@test "caches the cargo registry and build output" {
    grep -q "Swatinem/rust-cache" "$WF"
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
