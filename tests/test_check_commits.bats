#!/usr/bin/env bats

load helpers/repo

setup() {
    SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"
    make_repo
    git checkout -q -b feature
}

@test "accepts a conventional English subject" {
    commit_file "a.txt" "x" "feat: add stock level endpoint"
    run "$SCRIPTS/check-commits.sh" main HEAD
    [ "$status" -eq 0 ]
}

@test "accepts a scope and a breaking-change marker" {
    commit_file "a.txt" "x" "feat(api)!: drop the legacy stock route"
    run "$SCRIPTS/check-commits.sh" main HEAD
    [ "$status" -eq 0 ]
}

@test "rejects a subject with no type" {
    commit_file "a.txt" "x" "added a new endpoint"
    run "$SCRIPTS/check-commits.sh" main HEAD
    [ "$status" -eq 1 ]
    [[ "$output" == *"added a new endpoint"* ]]
}

@test "rejects an unknown type" {
    commit_file "a.txt" "x" "wip: still working"
    run "$SCRIPTS/check-commits.sh" main HEAD
    [ "$status" -eq 1 ]
}

@test "rejects a French subject" {
    commit_file "a.txt" "x" "feat: ajouter la gestion du stock"
    run "$SCRIPTS/check-commits.sh" main HEAD
    [ "$status" -eq 1 ]
}

@test "checks every commit in the range" {
    commit_file "a.txt" "x" "feat: add first thing"
    commit_file "b.txt" "x" "broken subject"
    run "$SCRIPTS/check-commits.sh" main HEAD
    [ "$status" -eq 1 ]
    [[ "$output" == *"broken subject"* ]]
}

@test "ignores merge commits" {
    commit_file "a.txt" "x" "feat: add first thing"
    git checkout -q main
    commit_file "c.txt" "x" "fix: patch on main"
    git checkout -q feature
    git merge -q --no-ff -m "Merge branch 'main' into feature" main
    run "$SCRIPTS/check-commits.sh" main HEAD
    [ "$status" -eq 0 ]
}

@test "passes on an empty range" {
    run "$SCRIPTS/check-commits.sh" main HEAD
    [ "$status" -eq 0 ]
}

@test "validates a single subject in --subject mode" {
    run "$SCRIPTS/check-commits.sh" --subject "feat: add stock endpoint"
    [ "$status" -eq 0 ]
}

@test "rejects a bad single subject in --subject mode" {
    run "$SCRIPTS/check-commits.sh" --subject "added an endpoint"
    [ "$status" -eq 1 ]
}

@test "rejects a French single subject in --subject mode" {
    run "$SCRIPTS/check-commits.sh" --subject "feat: ajouter le stock"
    [ "$status" -eq 1 ]
}
