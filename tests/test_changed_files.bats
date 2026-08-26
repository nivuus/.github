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

@test "lists a renamed file under its new name" {
    commit_file "src/old.py" "x = 1"
    git checkout -q -b feature
    git mv "src/old.py" "src/new.py"
    printf 'x = 2\n' >> "src/new.py"
    git commit -q -am "refactor: rename module"

    run bash -c "source '$SCRIPTS/lib/changed-files.sh'; changed_files main HEAD"

    [ "$status" -eq 0 ]
    [ "$output" = "src/new.py" ]
}

@test "lists a copied file" {
    commit_file "src/a.py" "x = 1"
    git checkout -q -b feature
    cp "src/a.py" "src/b.py"
    git add "src/b.py"
    git commit -q -m "feat: add a second module"

    run bash -c "source '$SCRIPTS/lib/changed-files.sh'; changed_files main HEAD"

    [ "$status" -eq 0 ]
    [[ "$output" == *"src/b.py"* ]]
}
