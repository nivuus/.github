#!/usr/bin/env bats

load helpers/repo

setup() {
    SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"
    make_repo
}

@test "refuses to run outside a git repository" {
    cd "$(mktemp -d)"
    run "$SCRIPTS/release-notes.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not inside a git repository"* ]]
}

@test "lists every commit when no tag bounds the log" {
    commit_file "a.txt" "x" "feat: the first thing"
    commit_file "b.txt" "x" "fix: the second thing"
    run "$SCRIPTS/release-notes.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"feat: the first thing"* ]]
    [[ "$output" == *"fix: the second thing"* ]]
}

@test "lists only what came after the previous tag" {
    commit_file "a.txt" "x" "feat: before the tag"
    git tag -a v1.0.0 -m "release"
    commit_file "b.txt" "x" "fix: after the tag"
    run "$SCRIPTS/release-notes.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"fix: after the tag"* ]]
    [[ "$output" != *"feat: before the tag"* ]]
}

@test "carries the update command for the package" {
    commit_file "a.txt" "x" "feat: something"
    PACKAGE=home-stock run "$SCRIPTS/release-notes.sh"
    [[ "$output" == *"nivuus update home-stock"* ]]
}

# GitHub answers HTTP 422 "body is too long" above 125000 characters, AFTER the
# assets are built and attested, and `gh release create` makes the tag and the
# release in one call - so the whole release is lost. Measured on nivuus/desk:
# a first release over 1386 commits produced a 127215-character changelog.
@test "keeps the body under what the API accepts" {
    for i in $(seq 1 60); do
        commit_file "f$i.txt" "x" "feat: change number $i"
    done
    NOTES_BUDGET=400 run "$SCRIPTS/release-notes.sh"
    [ "$status" -eq 0 ]
    [ "${#output}" -lt 700 ]
}

# The direction of the truncation is the whole point, and it is the easy thing
# to get backwards: `git log` prints newest first, so the obvious-looking
# `tac | awk` keeps the OLDEST entries and drops the newest. That was measured
# doing exactly this while the script was written - 104 most recent commits of
# desk, HEAD included, silently gone.
@test "drops the oldest entries, never the newest" {
    for i in $(seq 1 60); do
        commit_file "f$i.txt" "x" "feat: change number $i"
    done
    NOTES_BUDGET=400 run "$SCRIPTS/release-notes.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"change number 60"* ]]
    [[ "$output" != *"change number 1 "* ]]
}

@test "says how many entries it dropped" {
    for i in $(seq 1 60); do
        commit_file "f$i.txt" "x" "feat: change number $i"
    done
    NOTES_BUDGET=400 run "$SCRIPTS/release-notes.sh"
    [[ "$output" == *"plus ancien(s), omis"* ]]
}

@test "says nothing about truncation when everything fits" {
    commit_file "a.txt" "x" "feat: the only thing"
    run "$SCRIPTS/release-notes.sh"
    [[ "$output" != *"omis"* ]]
}
