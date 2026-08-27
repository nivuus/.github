#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/ci.yml"
}

@test "socle CI workflow exists" {
    [ -f "$WF" ]
}

# The socle cannot call itself at @main: on a pull request, main does not yet
# contain the workflow under test. Local paths resolve at the commit being
# tested, which is what lets the socle police its own changes.
@test "socle calls its own workflows locally, not at main" {
    grep -q "uses: ./.github/workflows/policy.yml" "$WF"
    grep -q "uses: ./.github/workflows/security.yml" "$WF"
    run grep -q "nivuus/.github/.github/workflows" "$WF"
    [ "$status" -ne 0 ]
}

@test "socle runs its checks against its own commit" {
    grep -q 'socle-ref: ${{ github.sha }}' "$WF"
}
