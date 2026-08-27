#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/ci-rust.yml"
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

@test "passes github expressions through env, never into run blocks" {
    run grep -nE '^ +run:.*\$\{\{' "$WF"
    [ "$status" -ne 0 ]
}
