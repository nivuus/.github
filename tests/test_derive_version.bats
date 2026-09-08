#!/usr/bin/env bats

load helpers/repo

setup() {
    SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"
    make_repo
}

@test "prints the initial version when no tag exists" {
    run "$SCRIPTS/derive-version.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "1.0.0" ]
}

@test "honours an overridden initial version" {
    INITIAL_VERSION=0.1.0 run "$SCRIPTS/derive-version.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.0" ]
}

@test "bumps the minor version for a feat" {
    git tag -a v1.2.3 -m "release"
    commit_file "a.txt" "x" "feat: add the stock endpoint"
    run "$SCRIPTS/derive-version.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "1.3.0" ]
}

@test "bumps the patch version for a fix" {
    git tag -a v1.2.3 -m "release"
    commit_file "a.txt" "x" "fix: stop dropping the retained topic"
    run "$SCRIPTS/derive-version.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "1.2.4" ]
}

@test "treats perf and refactor as patches" {
    git tag -a v1.2.3 -m "release"
    commit_file "a.txt" "x" "perf: shrink the discovery payload"
    commit_file "b.txt" "x" "refactor: split the coordinator"
    run "$SCRIPTS/derive-version.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "1.2.4" ]
}

@test "bumps the major version for a bang marker" {
    git tag -a v1.2.3 -m "release"
    commit_file "a.txt" "x" "feat(cli)!: rename nivuus to nivuus-shell"
    run "$SCRIPTS/derive-version.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "2.0.0" ]
}

@test "bumps the major version for a BREAKING CHANGE footer" {
    git tag -a v1.2.3 -m "release"
    printf 'x\n' > a.txt
    git add a.txt
    git commit -q -m "feat: rework the manifest" -m "BREAKING CHANGE: source is required"
    run "$SCRIPTS/derive-version.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "2.0.0" ]
}

@test "a feat outranks a fix whatever the order" {
    git tag -a v1.2.3 -m "release"
    commit_file "a.txt" "x" "fix: correct the unit path"
    commit_file "b.txt" "x" "feat: add the update entity"
    run "$SCRIPTS/derive-version.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "1.3.0" ]
}

@test "exits 3 when nothing is releasable" {
    git tag -a v1.2.3 -m "release"
    commit_file "a.txt" "x" "docs: explain the release contract"
    commit_file "b.txt" "x" "chore: bump the linter"
    run "$SCRIPTS/derive-version.sh"
    [ "$status" -eq 3 ]
    [ -z "$output" ]
}

@test "ignores tags that are not versions" {
    git tag -a nightly -m "not a version"
    commit_file "a.txt" "x" "feat: add a thing"
    run "$SCRIPTS/derive-version.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "1.0.0" ]
}
