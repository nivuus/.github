#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/.."
}

@test "all health files are present" {
    [ -f "$ROOT/CONTRIBUTING.md" ]
    [ -f "$ROOT/SECURITY.md" ]
    [ -f "$ROOT/PULL_REQUEST_TEMPLATE.md" ]
    [ -f "$ROOT/dependabot.yml" ]
}

@test "CONTRIBUTING states the three coding rules" {
    grep -q "500" "$ROOT/CONTRIBUTING.md"
    grep -qi "anglais" "$ROOT/CONTRIBUTING.md"
    grep -qi "conventional commits" "$ROOT/CONTRIBUTING.md"
}

@test "CONTRIBUTING documents the escape hatch" {
    grep -q "policy: allow-fr" "$ROOT/CONTRIBUTING.md"
}

@test "SECURITY names a working reporting channel" {
    grep -qi "report a vulnerability" "$ROOT/SECURITY.md"
    # No invented contact address: the channel is GitHub's private reporting,
    # which needs no mailbox to exist. If a real security mailbox is created
    # later, add it here and relax this assertion deliberately.
    run grep -qE '[a-z]+@[a-z]+\.[a-z]+' "$ROOT/SECURITY.md"
    [ "$status" -ne 0 ]
}
