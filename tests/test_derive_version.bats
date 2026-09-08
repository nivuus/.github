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

@test "running outside a git repository exits 1" {
    cd /tmp
    run "$SCRIPTS/derive-version.sh"
    [ "$status" -eq 1 ]
    [ "$output" = "fatal: not a git repository" ]
}

@test "a shallow clone exits 1 instead of printing initial version" {
    git tag -a v1.2.3 -m "release"
    commit_file "a.txt" "x" "feat: add the stock endpoint"
    REPO_BACKUP="$REPO"
    SHALLOW_DIR="$(mktemp -d)"
    cd "$SHALLOW_DIR"
    git clone --depth 1 "file://${REPO_BACKUP}" .
    run "$SCRIPTS/derive-version.sh"
    [ "$status" -eq 1 ]
    [ "$output" = "fatal: shallow clone detected; full history or fetched tags required for version derivation" ]
}

@test "a BREAKING CHANGE footer is honoured on every run, not just some (pipe-race regression)" {
    # scripts/derive-version.sh used to pipe `git log ... | grep -q ...`
    # under `set -uo pipefail`. grep -q exits at its FIRST match and closes
    # its end of the pipe; if git log is still writing when that happens, it
    # takes SIGPIPE, the pipeline status becomes 141, and the surrounding
    # `&&` reads as false - so the major bump got dropped at random, with the
    # exact same commit history passing on one run and failing on the next.
    #
    # This is a pure scheduling race, not a data-size threshold, but on THIS
    # machine's git/kernel/pipe-buffer combination a single small commit
    # essentially never triggers it (measured: 0 failures in hundreds of
    # tries). What reliably wins the race here is a history where the
    # breaking-change commit is the newest one - so its body is the FIRST
    # thing git log writes and grep can exit right away - followed by
    # hundreds of KB of older commits git log still has left to write,
    # forcing it past the pipe buffer and into a write that lands after grep
    # has already gone. `git fast-import` builds that history in one shot,
    # far faster than 500 individual `git commit` calls.
    #
    # Measured against the pre-fix pipeline: 30/30 runs of this exact
    # scenario returned "1.3.0" (the breaking change silently downgraded to
    # a feat's minor bump) instead of "2.0.0". Against the fix: 0/30.
    git tag -a v1.2.3 -m "release"
    local first_sha
    first_sha="$(git rev-parse HEAD)"

    local stream filler i body breaking
    stream="$(mktemp)"
    printf -v filler '%*s' 1500 ""
    filler="${filler// /z}"
    {
        for i in $(seq 1 500); do
            body="chore: filler ${i}"$'\n\n'"${filler}"$'\n'
            printf 'commit refs/heads/main\n'
            printf 'committer Test <test@nivuus.local> %d +0000\n' "$((1000000000 + i))"
            printf 'data %d\n%s' "${#body}" "$body"
            if [ "$i" -eq 1 ]; then
                printf 'from %s\n' "$first_sha"
            fi
            printf 'M 100644 inline f%d.txt\ndata 1\nx\n' "$i"
        done
        breaking="feat: rework the manifest"$'\n\n'"BREAKING CHANGE: source is required"$'\n'
        printf 'commit refs/heads/main\n'
        printf 'committer Test <test@nivuus.local> %d +0000\n' "$((1000000000 + 501))"
        printf 'data %d\n%s' "${#breaking}" "$breaking"
        printf 'M 100644 inline last.txt\ndata 1\nx\n'
    } > "$stream"
    git fast-import --quiet < "$stream" >/dev/null 2>&1
    rm -f "$stream"

    for i in $(seq 1 25); do
        run "$SCRIPTS/derive-version.sh"
        [ "$status" -eq 0 ]
        [ "$output" = "2.0.0" ]
    done
}

@test "feat before fix still yields minor bump (order independence)" {
    git tag -a v1.2.3 -m "release"
    commit_file "a.txt" "x" "feat: add the update entity"
    commit_file "b.txt" "x" "fix: correct the unit path"
    run "$SCRIPTS/derive-version.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "1.3.0" ]
}
