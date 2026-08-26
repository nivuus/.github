#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../scripts/lib"
    WORK="$(mktemp -d)"
    cd "$WORK" || return 1
}

teardown() {
    [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

# scan <lang> <filename> — run the engine over the file already written.
scan() {
    gawk -v lang="$1" -v words="$LIB/french-words.txt" -f "$LIB/english.awk" "$2"
}

@test "accepts an English comment" {
    printf '# Compute the total stock level\nx = 1\n' > a.py
    run scan py a.py
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "rejects an accented comment" {
    printf '# Calcule le niveau de stock général\nx = 1\n' > a.py
    run scan py a.py
    [ "$status" -eq 1 ]
    [[ "$output" == 1:* ]]
}

@test "rejects an unaccented French comment via the word list" {
    printf '# verifier le stock avant de continuer\nx = 1\n' > a.py
    run scan py a.py
    [ "$status" -eq 1 ]
}

@test "accepts a French user-facing string" {
    printf 'print("Stock insuffisant, veuillez réessayer")\n' > a.py
    run scan py a.py
    [ "$status" -eq 0 ]
}

@test "rejects a French identifier" {
    printf 'def verifier_stock():\n    pass\n' > a.py
    run scan py a.py
    [ "$status" -eq 1 ]
}

@test "rejects a French camelCase identifier" {
    printf 'const verifierStock = () => {};\n' > a.ts
    run scan ts a.ts
    [ "$status" -eq 1 ]
}

@test "rejects a French Python docstring" {
    printf 'def f():\n    """Vérifie le stock."""\n    pass\n' > a.py
    run scan py a.py
    [ "$status" -eq 1 ]
}

@test "rejects a French multi-line docstring" {
    printf 'def f():\n    """\n    Vérifie le stock disponible.\n    """\n    pass\n' > a.py
    run scan py a.py
    [ "$status" -eq 1 ]
}

@test "honours the allow-fr escape hatch" {
    printf '# Calcule le niveau de stock  # policy: allow-fr\nx = 1\n' > a.py
    run scan py a.py
    [ "$status" -eq 0 ]
}

@test "does not treat a hash inside a string as a comment" {
    printf 'url = "https://x/#ancre-française"\n' > a.py
    run scan py a.py
    [ "$status" -eq 0 ]
}

@test "rejects a French slash comment in rust" {
    printf '// Récupère la configuration\nfn main() {}\n' > a.rs
    run scan rs a.rs
    [ "$status" -eq 1 ]
}

@test "accepts an English shell script" {
    printf '#!/usr/bin/env bash\n# Print the current version\necho "Version actuelle"\n' > a.sh
    run scan sh a.sh
    [ "$status" -eq 0 ]
}

@test "reports every offending line" {
    printf '# Vérifie le stock\nx = 1\n# Affiche le résultat\n' > a.py
    run scan py a.py
    [ "$status" -eq 1 ]
    [ "${#lines[@]}" -eq 2 ]
}

# Known blind spot: a French comment with no accent and no listed word is not
# detected. The list covers common vocabulary, not the whole language. Task 15
# measures how often this occurs on real code; if it is frequent, the
# heuristic changes and this test changes with it.
@test "does not detect unaccented French outside the word list" {
    printf '# Boucle sur les items entrants\nx = 1\n' > a.py
    run scan py a.py
    [ "$status" -eq 0 ]
}

@test "ignores an allow-fr marker inside a string literal" {
    printf 'print("policy: allow-fr")  # Vérifie le stock\nx = 1\n' > a.py
    run scan py a.py
    [ "$status" -eq 1 ]
}

@test "still honours the marker followed by a reason" {
    printf '# Nom de la société Vérifie  # policy: allow-fr raison métier\nx = 1\n' > a.py
    run scan py a.py
    [ "$status" -eq 0 ]
}

@test "rejects a French docstring in triple single quotes" {
    printf "def f():\n    '''Vérifie le stock.'''\n    pass\n" > a.py
    run scan py a.py
    [ "$status" -eq 1 ]
}

@test "rejects a French multi-line docstring in triple single quotes" {
    printf "def f():\n    '''\n    Vérifie le stock disponible.\n    '''\n    pass\n" > a.py
    run scan py a.py
    [ "$status" -eq 1 ]
}

@test "accepts an English docstring in triple single quotes" {
    printf "def f():\n    '''Return the current stock level.'''\n    pass\n" > a.py
    run scan py a.py
    [ "$status" -eq 0 ]
}
