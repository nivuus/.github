#!/usr/bin/env bats

setup() {
    SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"
    WORK="$(mktemp -d)"
    cd "$WORK" || return 1
}

teardown() {
    [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

@test "accepts English source" {
    printf '# Compute the stock level\nx = 1\n' > app.py
    run bash -c "echo app.py | '$SCRIPTS/check-english.sh'"
    [ "$status" -eq 0 ]
}

@test "rejects a French comment and names the file and line" {
    printf 'x = 1\n# Calcule le stock\n' > app.py
    run bash -c "echo app.py | '$SCRIPTS/check-english.sh'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"app.py:2:"* ]]
}

@test "picks the right dialect per extension" {
    printf '// Récupère la configuration\nfn main() {}\n' > main.rs
    run bash -c "echo main.rs | '$SCRIPTS/check-english.sh'"
    [ "$status" -eq 1 ]
}

@test "skips markdown documentation" {
    printf '# Guide utilisateur français\n' > README.md
    run bash -c "echo README.md | '$SCRIPTS/check-english.sh'"
    [ "$status" -eq 0 ]
}

@test "skips test files" {
    mkdir -p tests
    printf '# Vérifie le comportement\n' > tests/test_app.py
    run bash -c "echo tests/test_app.py | '$SCRIPTS/check-english.sh'"
    [ "$status" -eq 0 ]
}

@test "skips a path that no longer exists" {
    run bash -c "echo gone.py | '$SCRIPTS/check-english.sh'"
    [ "$status" -eq 0 ]
}

@test "checks every file in the list" {
    printf '# Calcule le stock\n' > a.py
    printf '// Affiche le total\n' > b.ts
    run bash -c "printf 'a.py\nb.ts\n' | '$SCRIPTS/check-english.sh'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"a.py"* ]]
    [[ "$output" == *"b.ts"* ]]
}
