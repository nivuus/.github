#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/policy.yml"
}

@test "policy workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "job id stays 'policy' so branch protection keeps matching" {
    grep -qE '^  policy:' "$WF"
}

@test "fetches full history for the diff and the commit range" {
    grep -q "fetch-depth: 0" "$WF"
}

@test "checks out the socle to reach its scripts" {
    grep -q "repository: nivuus/.github" "$WF"
}

@test "installs gawk, required by the French detector" {
    grep -q "gawk" "$WF"
}

@test "runs all three checks" {
    grep -q "check-file-size.sh" "$WF"
    grep -q "check-english.sh" "$WF"
    grep -q "check-commits.sh" "$WF"
}

@test "passes github expressions through env, never into run blocks" {
    run grep -nE '^ +run:.*\$\{\{' "$WF"
    [ "$status" -ne 0 ]
}
