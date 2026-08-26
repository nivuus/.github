#!/usr/bin/env bats

load helpers/repo

setup() {
    SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"
    make_repo
}

# Write a file with N lines of valid-looking content.
write_lines() {
    local path="$1" n="$2" i
    mkdir -p "$(dirname "$path")"
    : > "$path"
    for ((i = 1; i <= n; i++)); do
        printf 'x = %d\n' "$i" >> "$path"
    done
}

@test "accepts a source file at exactly the limit" {
    write_lines "src/app.py" 500

    run bash -c "echo src/app.py | '$SCRIPTS/check-file-size.sh'"

    [ "$status" -eq 0 ]
}

@test "rejects a source file over the limit" {
    write_lines "src/app.py" 501

    run bash -c "echo src/app.py | '$SCRIPTS/check-file-size.sh'"

    [ "$status" -eq 1 ]
    [[ "$output" == *"src/app.py"* ]]
    [[ "$output" == *"501"* ]]
}

@test "exempts a file under tests/" {
    write_lines "tests/test_app.py" 900

    run bash -c "echo tests/test_app.py | '$SCRIPTS/check-file-size.sh'"

    [ "$status" -eq 0 ]
}

@test "exempts a spec file outside tests/" {
    write_lines "src/app.spec.ts" 900

    run bash -c "echo src/app.spec.ts | '$SCRIPTS/check-file-size.sh'"

    [ "$status" -eq 0 ]
}

@test "exempts generated lockfiles" {
    write_lines "package-lock.json" 9000
    write_lines "Cargo.lock" 9000

    run bash -c "printf 'package-lock.json\nCargo.lock\n' | '$SCRIPTS/check-file-size.sh'"

    [ "$status" -eq 0 ]
}

@test "exempts files under a generated directory" {
    write_lines "src/generated/api.ts" 900

    run bash -c "echo src/generated/api.ts | '$SCRIPTS/check-file-size.sh'"

    [ "$status" -eq 0 ]
}

@test "ignores non-source extensions" {
    write_lines "docs/guide.md" 2000

    run bash -c "echo docs/guide.md | '$SCRIPTS/check-file-size.sh'"

    [ "$status" -eq 0 ]
}

@test "ignores a path that no longer exists" {
    run bash -c "echo src/vanished.py | '$SCRIPTS/check-file-size.sh'"

    [ "$status" -eq 0 ]
}

@test "reports every violation, not just the first" {
    write_lines "src/a.py" 600
    write_lines "src/b.rs" 700

    run bash -c "printf 'src/a.py\nsrc/b.rs\n' | '$SCRIPTS/check-file-size.sh'"

    [ "$status" -eq 1 ]
    [[ "$output" == *"src/a.py"* ]]
    [[ "$output" == *"src/b.rs"* ]]
}
