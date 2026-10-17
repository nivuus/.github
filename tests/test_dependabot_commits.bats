#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../scripts/dependabot-commits.sh"
}

# commit <sha> <author-login> <committer-login> <verified>: one item of
# GET /repos/{owner}/{repo}/pulls/{n}/commits, reduced to what is checked.
commit() {
    printf '{"sha":"%s","author":{"login":"%s"},"committer":{"login":"%s"},"commit":{"verification":{"verified":%s}}}' \
        "$1" "$2" "$3" "$4"
}

# What Dependabot itself pushes: authored by it, committed and signed by GitHub.
dependabot_commit() {
    commit "$1" "dependabot[bot]" web-flow true
}

# check <page>...: each argument is one page, printed back to back the way
# `gh api --paginate` prints them.
check() {
    run "$SCRIPT" <<< "$(printf '%s\n' "$@")"
}

@test "a branch only Dependabot wrote passes" {
    check "[$(dependabot_commit aaaaaaaaaaaaaaaa)]"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dependabot aaaaaaaaaaaa"* ]]
}

# nivuus/desk#7: the same commit re-created unsigned by a human's rebase.
@test "a branch rebased by a human waits for review" {
    check "[$(commit bbbbbbbbbbbbbbbb "dependabot[bot]" maximeallanic false)]"
    [ "$status" -eq 3 ]
    [[ "$output" == *"committed by maximeallanic"* ]]
}

@test "a human fix commit pushed on top waits for review" {
    check "[$(dependabot_commit aaaaaaaaaaaaaaaa),$(commit cccccccccccccccc maximeallanic maximeallanic true)]"
    [ "$status" -eq 3 ]
    [[ "$output" == *"dependabot aaaaaaaaaaaa"* ]]
    [[ "$output" == *"foreign    cccccccccccc: authored by maximeallanic"* ]]
}

# fetch-metadata refuses an unverified first commit; this must refuse it too.
@test "an unsigned commit from GitHub waits for review" {
    check "[$(commit dddddddddddddddd "dependabot[bot]" web-flow false)]"
    [ "$status" -eq 3 ]
    [[ "$output" == *"signature not verified"* ]]
}

# A human can sign a commit that merely names Dependabot as its author.
@test "a signed commit claiming dependabot but committed by a human waits for review" {
    check "[$(commit eeeeeeeeeeeeeeee "dependabot[bot]" mallory true)]"
    [ "$status" -eq 3 ]
    [[ "$output" == *"committed by mallory"* ]]
}

# fetch-metadata only looks at the first commit; every one is checked here.
@test "a foreign commit is caught whatever its position, across pages" {
    check "[$(dependabot_commit aaaaaaaaaaaaaaaa)]" \
        "[$(dependabot_commit bbbbbbbbbbbbbbbb),$(commit ffffffffffffffff "" "" false)]"
    [ "$status" -eq 3 ]
    [[ "$output" == *"dependabot bbbbbbbbbbbb"* ]]
    [[ "$output" == *"authored by an unknown account"* ]]
}

@test "a commit without verification data is not trusted" {
    check '[{"sha":"abababababababab","author":{"login":"dependabot[bot]"},"committer":{"login":"web-flow"},"commit":{}}]'
    [ "$status" -eq 3 ]
    [[ "$output" == *"signature not verified"* ]]
}

@test "unparsable input is an error, not a review" {
    check "not json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"fatal"* ]]
}

@test "an object instead of a commits array is an error" {
    check '{"message":"Not Found","status":"404"}'
    [ "$status" -eq 1 ]
}

@test "an array of something other than commits is an error" {
    check '["a","b"]'
    [ "$status" -eq 1 ]
}

@test "no commit at all is an error" {
    check "[]"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no commit"* ]]
}
