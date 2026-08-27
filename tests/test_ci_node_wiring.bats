#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/ci-node.yml"
}

@test "ci-node workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "exposes an overridable node version" {
    grep -q "node-version:" "$WF"
}

# marketplace keeps its package.json under frontend/.
@test "exposes an overridable working directory" {
    grep -q "working-directory:" "$WF"
}

@test "exposes an overridable script list" {
    grep -q "scripts:" "$WF"
}

# A repository without a lint script must not fail on npm run lint.
@test "runs a script only when package.json defines it" {
    grep -q "npm pkg get" "$WF"
}

@test "prefers a reproducible install" {
    grep -q "npm ci" "$WF"
}

@test "passes github expressions through env, never into run blocks" {
    run grep -nE '^ +run:.*\$\{\{' "$WF"
    [ "$status" -ne 0 ]
}
