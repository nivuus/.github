#!/usr/bin/env bats

load helpers/repo

setup() {
    SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"
    make_repo
}

@test "lists a file added on the branch" {
    git checkout -q -b feature
    commit_file "src/app.py" "print('hi')"

    run bash -c "source '$SCRIPTS/lib/changed-files.sh'; changed_files main HEAD"

    [ "$status" -eq 0 ]
    [ "$output" = "src/app.py" ]
}

@test "lists a modified file" {
    commit_file "src/app.py" "print('hi')"
    git checkout -q -b feature
    commit_file "src/app.py" "print('bye')" "fix: change greeting"

    run bash -c "source '$SCRIPTS/lib/changed-files.sh'; changed_files main HEAD"

    [ "$status" -eq 0 ]
    [ "$output" = "src/app.py" ]
}

@test "ignores a deleted file" {
    commit_file "src/gone.py" "print('hi')"
    git checkout -q -b feature
    git rm -q "src/gone.py"
    git commit -q -m "chore: remove file"

    run bash -c "source '$SCRIPTS/lib/changed-files.sh'; changed_files main HEAD"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "returns success with no changes at all" {
    git checkout -q -b feature

    run bash -c "source '$SCRIPTS/lib/changed-files.sh'; changed_files main HEAD"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}
