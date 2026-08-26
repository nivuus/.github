# Socle d'uniformisation Nivuus — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construire dans `nivuus/.github` le socle de règles partagées (codage, sécurité, CI) et le valider en conditions réelles sur le dépôt pilote `shell`.

**Architecture:** Des scripts shell autonomes et testés portent chaque règle. Des workflows réutilisables (`workflow_call`) les exécutent. Un script idempotent applique la configuration serveur via l'API GitHub. Les dépôts consommateurs n'embarquent qu'un appelant de dix lignes.

**Tech Stack:** Bash, awk, bats-core 1.11, GitHub Actions (`workflow_call`), CLI `gh`, gitleaks, shellcheck.

**Spec:** `docs/superpowers/specs/2026-08-26-uniformisation-org-nivuus-design.md`

**Périmètre de ce plan:** étapes 1 à 3 du § 8 du spec. L'extension aux sept autres dépôts (étapes 4-5) fera l'objet d'un plan distinct.

## Global Constraints

- Limite de taille : **500 lignes** par fichier source. Extensions concernées : `.sh`, `.zsh`, `.py`, `.ts`, `.tsx`, `.js`, `.rs`.
- Les fichiers de test sont **exemptés** de la limite de taille.
- Le code (identifiants, commentaires, docstrings), les messages de commit et les noms de branches sont en **anglais**. Les chaînes affichées à l'utilisateur, les README, CHANGELOG et `docs/` restent en **français**.
- Marqueur d'échappement pour la règle « anglais » : `policy: allow-fr` en fin de ligne.
- Format des commits : Conventional Commits, **bloquant**.
- Les contrôles ne s'appliquent qu'aux fichiers **ajoutés ou modifiés** dans la pull request (`git diff --name-only --diff-filter=AM origin/main...HEAD`).
- Branche principale : `main` partout.
- `enforce_admins: true`, 0 approbation requise, squash-merge seul, historique linéaire.
- Le code de ce dépôt est soumis à ses propres règles : tout script écrit ici est en anglais et fait moins de 500 lignes.

## File Structure

| Fichier | Responsabilité |
|---|---|
| `scripts/lib/changed-files.sh` | Lister les fichiers modifiés dans la PR |
| `scripts/lib/french-words.txt` | Mots français fréquents sans accent |
| `scripts/lib/english.awk` | Détecter le français dans commentaires et identifiants d'un fichier |
| `scripts/check-file-size.sh` | Règle des 500 lignes |
| `scripts/check-english.sh` | Règle « anglais dans le code » |
| `scripts/check-commits.sh` | Règle Conventional Commits |
| `scripts/apply-org-config.sh` | Configuration serveur via API GitHub |
| `tests/helpers/repo.bash` | Fabrique de dépôts git jetables pour les tests |
| `tests/*.bats` | Tests bats, un fichier par script |
| `.github/workflows/policy.yml` | Workflow réutilisable : règles de codage |
| `.github/workflows/security.yml` | Workflow réutilisable : secrets et dépendances |
| `.github/workflows/ci-shell.yml` | Workflow réutilisable : Bash/Zsh |
| `.github/workflows/ci.yml` | CI propre au dépôt `.github` |
| `CONTRIBUTING.md`, `SECURITY.md`, `PULL_REQUEST_TEMPLATE.md`, `dependabot.yml` | Fichiers de santé communs |

---

### Task 1: Harnais de test et détection des fichiers modifiés

Tous les contrôles opèrent sur « les fichiers modifiés dans la PR ». Cette tâche fournit la brique commune et le harnais qui permettra de tester les suivantes.

**Files:**
- Create: `scripts/lib/changed-files.sh`
- Create: `tests/helpers/repo.bash`
- Test: `tests/test_changed_files.bats`

**Interfaces:**
- Consumes: rien.
- Produces:
  - `changed_files <base_ref> <head_ref>` — écrit sur stdout un chemin par ligne, les fichiers ajoutés ou modifiés entre la base et la tête. Retourne 0 même si la liste est vide.
  - Helper de test `make_repo <dir>` — crée un dépôt git initialisé avec un commit vide sur `main`, et positionne `$REPO`.
  - Helper de test `commit_file <path> <content> [message]` — écrit le fichier, l'ajoute et le commite dans `$REPO`.

- [ ] **Step 1: Write the failing test**

Créer `tests/helpers/repo.bash` :

```bash
# Test helpers: build throwaway git repositories.

make_repo() {
    REPO="$(mktemp -d)"
    cd "$REPO" || return 1
    git init -q -b main .
    git config user.email "test@nivuus.local"
    git config user.name "Test"
    git commit -q --allow-empty -m "chore: initial commit"
}

commit_file() {
    local path="$1" content="$2" message="${3:-chore: add file}"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    git add "$path"
    git commit -q -m "$message"
}

teardown() {
    [ -n "${REPO:-}" ] && rm -rf "$REPO"
}
```

Créer `tests/test_changed_files.bats` :

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_changed_files.bats`
Expected: FAIL — `changed-files.sh: No such file or directory`

- [ ] **Step 3: Write minimal implementation**

Créer `scripts/lib/changed-files.sh` :

```bash
#!/usr/bin/env bash
# List files added or modified between two refs.

changed_files() {
    local base="${1:-origin/main}"
    local head="${2:-HEAD}"
    git diff --name-only --diff-filter=AM "${base}...${head}"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_changed_files.bats`
Expected: PASS — 4 tests

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/changed-files.sh tests/helpers/repo.bash tests/test_changed_files.bats
git commit -m "feat: add changed-files helper and bats test harness"
```

---

### Task 2: Règle des 500 lignes

**Files:**
- Create: `scripts/check-file-size.sh`
- Test: `tests/test_check_file_size.bats`

**Interfaces:**
- Consumes: `changed_files` (Task 1).
- Produces:
  - `scripts/check-file-size.sh` — lit une liste de chemins sur stdin, un par ligne. Sortie 0 si tout est conforme, 1 sinon. Chaque violation produit une ligne `<path>: <n> lines (max 500)` sur stdout.
  - `MAX_LINES=500`, surchargeable par la variable d'environnement `MAX_LINES`.

Le fichier de test est reconnu par son chemin ou son nom : un segment `test/` ou `tests/`, ou un nom correspondant à `test_*`, `*_test.*`, `*.test.*`, `*.spec.*`.

- [ ] **Step 1: Write the failing test**

Créer `tests/test_check_file_size.bats` :

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_check_file_size.bats`
Expected: FAIL — `check-file-size.sh: No such file or directory`

- [ ] **Step 3: Write minimal implementation**

Créer `scripts/check-file-size.sh` (rendre exécutable : `chmod +x`) :

```bash
#!/usr/bin/env bash
# Enforce the maximum source file length.
# Reads one path per line on stdin. Exits 1 if any file exceeds the limit.
set -uo pipefail

MAX_LINES="${MAX_LINES:-500}"

readonly SOURCE_RE='\.(sh|zsh|py|ts|tsx|js|rs)$'
readonly TEST_RE='(^|/)tests?/|(^|/)test_[^/]*$|_test\.[^/]+$|\.test\.[^/]+$|\.spec\.[^/]+$'
readonly GENERATED_RE='(^|/)generated/|(^|/)(package-lock\.json|Cargo\.lock)$|\.pb\.rs$'

is_checked() {
    local path="$1"
    [[ "$path" =~ $GENERATED_RE ]] && return 1
    [[ "$path" =~ $TEST_RE ]] && return 1
    [[ "$path" =~ $SOURCE_RE ]] || return 1
    return 0
}

main() {
    local path lines failed=0

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ -f "$path" ] || continue
        is_checked "$path" || continue

        lines=$(wc -l < "$path")
        if [ "$lines" -gt "$MAX_LINES" ]; then
            printf '%s: %d lines (max %d) — split this file into focused units\n' \
                "$path" "$lines" "$MAX_LINES"
            failed=1
        fi
    done

    return "$failed"
}

main "$@"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_check_file_size.bats`
Expected: PASS — 9 tests

- [ ] **Step 5: Commit**

```bash
git add scripts/check-file-size.sh tests/test_check_file_size.bats
git commit -m "feat: enforce 500-line limit on changed source files"
```

---

### Task 3: Détection du français — moteur awk et liste de mots

C'est la règle la plus délicate du socle : il faut refuser un commentaire français sans toucher aux chaînes d'interface, qui doivent rester en français. Cette tâche livre le moteur ; la Task 4 l'habille en script utilisable.

**Files:**
- Create: `scripts/lib/french-words.txt`
- Create: `scripts/lib/english.awk`
- Test: `tests/test_english_awk.bats`

**Interfaces:**
- Consumes: rien.
- Produces: `gawk -v lang=<py|sh|rs|ts|js> -v words=<path> -f scripts/lib/english.awk <file>` — écrit une ligne `<numéro>: <extrait>` par ligne fautive, et sort en 1 si au moins une ligne est fautive, 0 sinon.

**Notes de conception**

- `gawk` est requis, pas `mawk` : la détection des caractères accentués passe par une classe de caractères UTF-8 que mawk, l'awk par défaut d'Ubuntu, ne gère pas. Les workflows installeront `gawk` explicitement.
- Les littéraux de chaîne sont **blanchis, pas supprimés** — chaque caractère est remplacé par une espace. La longueur de la ligne est préservée, ce qui permet ensuite de localiser le marqueur de commentaire à la bonne position sans confondre un `#` réel avec un `#` situé dans une chaîne.
- Les docstrings Python sont traités à part, par un compteur d'état sur `"""`. Sans cela le blanchiment les effacerait et un docstring français passerait au travers, alors que le spec les veut en anglais.
- Le camelCase est découpé avant la comparaison, sinon `verifierStock` échapperait à la liste de mots.
- Seuls les mots français sans homographe anglais figurent dans la liste. `message`, `table`, `date`, `port`, `fin`, `car`, `plus` en sont délibérément absents : ce sont des mots anglais valides et les inclure produirait un flot de faux positifs.

- [ ] **Step 1: Write the failing test**

Créer `tests/test_english_awk.bats` :

```bash
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
    printf '# Calcule le niveau de stock total\nx = 1\n' > a.py
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
    printf '# Calcule le stock\nx = 1\n# Affiche le résultat\n' > a.py
    run scan py a.py
    [ "$status" -eq 1 ]
    [ "${#lines[@]}" -eq 2 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_english_awk.bats`
Expected: FAIL — `gawk: fatal: can't open source file .../english.awk`

Si `gawk` est absent de la machine : `sudo apt-get install -y gawk`.

- [ ] **Step 3a: Write the word list**

Créer `scripts/lib/french-words.txt` :

```
# Frequent French words with no valid English homograph.
# Accented words are caught separately and do not belong here.
afficher
ajouter
aucune
avant
avec
calculer
cette
chacun
chaine
chaque
charger
chercher
colonne
comme
courant
creer
dans
demarrer
dernier
donnee
donnees
dossier
ecrire
effacer
elles
enregistrer
ensuite
erreur
essai
fichier
fonction
initialiser
lancer
lecture
lire
liste
longueur
lorsque
mettre
modifier
nombre
nouveau
nouvelle
obtenir
parametre
permet
peut
plusieurs
pour
precedent
premier
recherche
recuperer
renvoie
renvoyer
repertoire
resultat
retourne
retourner
sauvegarder
selon
seulement
sinon
sortie
sous
suivant
supprimer
taille
tableau
tous
toujours
toutes
utilisateur
utiliser
valeur
verifier
verification
vider
```

- [ ] **Step 3b: Write the engine**

Créer `scripts/lib/english.awk` :

```awk
# Detect French in comments, docstrings and identifiers.
# Usage: gawk -v lang=py -v words=french-words.txt -f english.awk FILE
# Exits 1 when at least one line is flagged.

BEGIN {
    while ((getline word < words) > 0) {
        if (word == "" || word ~ /^#/) continue
        french[tolower(word)] = 1
    }
    close(words)
    accented = "[éèêëàâäîïôöùûüÿçœæÉÈÊËÀÂÄÎÏÔÖÙÛÜŸÇŒÆ]"
    indoc = 0
    found = 0
}

# Replace the contents of string literals with spaces, keeping the
# original length so column positions stay meaningful.
function blank_strings(s,    out, i, c, q, esc, n) {
    out = ""; q = ""; esc = 0
    n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q != "") {
            if (esc)          { esc = 0; out = out " "; continue }
            if (c == "\\")    { esc = 1; out = out " "; continue }
            if (c == q)       { q = "";  out = out c;   continue }
            out = out " "
        } else {
            if (c == "\"" || c == "'" || c == "`") { q = c; out = out c; continue }
            out = out c
        }
    }
    return out
}

function marker() {
    return (lang == "py" || lang == "sh") ? "#" : "//"
}

function report(n, text) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", text)
    printf "%d: %s\n", n, text
    found = 1
}

function is_french(text,    spaced, lower, i, nw, parts) {
    if (text ~ accented) return 1
    spaced = gensub(/([a-z0-9])([A-Z])/, "\\1 \\2", "g", text)
    lower = tolower(spaced)
    gsub(/[^a-z0-9]+/, " ", lower)
    nw = split(lower, parts, " ")
    for (i = 1; i <= nw; i++) {
        if (parts[i] in french) return 1
    }
    return 0
}

/policy:[[:space:]]*allow-fr/ { next }

{
    # Python docstrings are handled before blanking, which would erase them.
    if (lang == "py") {
        copy = $0
        delims = gsub(/"""/, "", copy)
        if (indoc) {
            if (delims % 2 == 1) indoc = 0
            if (is_french($0)) report(FNR, $0)
            next
        }
        if (delims % 2 == 1) indoc = 1
        if (delims > 0) {
            if (is_french($0)) report(FNR, $0)
            next
        }
    }

    blanked = blank_strings($0)
    idx = index(blanked, marker())

    if (idx > 0) {
        comment = substr($0, idx)
        code = substr(blanked, 1, idx - 1)
    } else {
        comment = ""
        code = blanked
    }

    if (is_french(comment) || is_french(code)) report(FNR, $0)
}

END { exit found }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_english_awk.bats`
Expected: PASS — 13 tests

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/french-words.txt scripts/lib/english.awk tests/test_english_awk.bats
git commit -m "feat: add French detection engine for comments and identifiers"
```

---

### Task 4: Règle « anglais dans le code »

Habille le moteur de la Task 3 en contrôle utilisable sur une liste de fichiers, avec la correspondance extension vers langage et les exemptions de périmètre.

**Files:**
- Create: `scripts/check-english.sh`
- Test: `tests/test_check_english.bats`

**Interfaces:**
- Consumes: `scripts/lib/english.awk`, `scripts/lib/french-words.txt` (Task 3).
- Produces: `scripts/check-english.sh` — lit une liste de chemins sur stdin, un par ligne. Sortie 0 si conforme, 1 sinon. Chaque violation produit `<path>:<ligne>: <extrait>`.

Périmètre : mêmes extensions que la règle de taille. Les fichiers `.md`, la documentation et les fichiers de test **sont exclus** — le spec laisse README, CHANGELOG et `docs/` en français, et un test peut légitimement contenir des chaînes françaises attendues.

- [ ] **Step 1: Write the failing test**

Créer `tests/test_check_english.bats` :

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_check_english.bats`
Expected: FAIL — `check-english.sh: No such file or directory`

- [ ] **Step 3: Write minimal implementation**

Créer `scripts/check-english.sh` (`chmod +x`) :

```bash
#!/usr/bin/env bash
# Enforce English in code: identifiers, comments and docstrings.
# Reads one path per line on stdin. Exits 1 on any violation.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENGINE="${SELF_DIR}/lib/english.awk"
readonly WORDS="${SELF_DIR}/lib/french-words.txt"

readonly TEST_RE='(^|/)tests?/|(^|/)test_[^/]*$|_test\.[^/]+$|\.test\.[^/]+$|\.spec\.[^/]+$'
readonly GENERATED_RE='(^|/)generated/|\.pb\.rs$'

dialect_of() {
    case "$1" in
        *.py)          printf 'py' ;;
        *.sh|*.zsh)    printf 'sh' ;;
        *.rs)          printf 'rs' ;;
        *.ts|*.tsx)    printf 'ts' ;;
        *.js)          printf 'js' ;;
        *)             return 1 ;;
    esac
}

main() {
    local path lang out failed=0

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ -f "$path" ] || continue
        [[ "$path" =~ $GENERATED_RE ]] && continue
        [[ "$path" =~ $TEST_RE ]] && continue
        lang="$(dialect_of "$path")" || continue

        if ! out="$(gawk -v lang="$lang" -v words="$WORDS" -f "$ENGINE" "$path")"; then
            printf '%s\n' "$out" | sed "s|^|${path}:|"
            failed=1
        fi
    done

    if [ "$failed" -eq 1 ]; then
        printf '\nCode must be written in English. User-facing strings stay in French.\n'
        printf 'Add "policy: allow-fr" at the end of a line to allow a legitimate exception.\n'
    fi

    return "$failed"
}

main "$@"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_check_english.bats`
Expected: PASS — 7 tests

- [ ] **Step 5: Commit**

```bash
git add scripts/check-english.sh tests/test_check_english.bats
git commit -m "feat: enforce English in changed source files"
```

---

### Task 5: Règle Conventional Commits

**Files:**
- Create: `scripts/check-commits.sh`
- Test: `tests/test_check_commits.bats`

**Interfaces:**
- Consumes: `scripts/lib/english.awk`, `scripts/lib/french-words.txt` (Task 3).
- Produces: `scripts/check-commits.sh <base_ref> <head_ref>` — inspecte le sujet de chaque commit de la plage. Sortie 0 si tous sont conformes, 1 sinon.

Types autorisés : `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`, `perf`, `build`, `style`, `revert`. Portée optionnelle entre parenthèses, `!` optionnel pour une rupture de compatibilité.

Les commits de merge sont ignorés : ils sont générés par GitHub et n'ont pas à suivre le format.

- [ ] **Step 1: Write the failing test**

Créer `tests/test_check_commits.bats` :

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_check_commits.bats`
Expected: FAIL — `check-commits.sh: No such file or directory`

- [ ] **Step 3: Write minimal implementation**

Créer `scripts/check-commits.sh` (`chmod +x`) :

```bash
#!/usr/bin/env bash
# Enforce Conventional Commits, with English subjects.
# Usage: check-commits.sh <base_ref> <head_ref>
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENGINE="${SELF_DIR}/lib/english.awk"
readonly WORDS="${SELF_DIR}/lib/french-words.txt"

readonly TYPES='feat|fix|chore|docs|refactor|test|ci|perf|build|style|revert'
readonly SUBJECT_RE="^(${TYPES})(\([a-z0-9._/-]+\))?!?: .+"

subject_is_french() {
    printf '%s\n' "$1" \
        | gawk -v lang=sh -v words="$WORDS" -f "$ENGINE" > /dev/null
    # The engine exits 1 when it flags a line.
    [ "$?" -eq 1 ]
}

main() {
    local base="${1:-origin/main}" head="${2:-HEAD}"
    local subject failed=0

    while IFS= read -r subject; do
        [ -n "$subject" ] || continue

        if ! [[ "$subject" =~ $SUBJECT_RE ]]; then
            printf 'Not a conventional commit: %s\n' "$subject"
            failed=1
            continue
        fi

        if subject_is_french "${subject#*: }"; then
            printf 'Commit subject must be in English: %s\n' "$subject"
            failed=1
        fi
    done < <(git log --no-merges --format='%s' "${base}..${head}")

    if [ "$failed" -eq 1 ]; then
        printf '\nExpected format: <type>(<scope>)!: <english subject>\n'
        printf 'Allowed types: %s\n' "${TYPES//|/, }"
    fi

    return "$failed"
}

main "$@"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_check_commits.bats`
Expected: PASS — 8 tests

- [ ] **Step 5: Commit**

```bash
git add scripts/check-commits.sh tests/test_check_commits.bats
git commit -m "feat: enforce conventional commits with English subjects"
```

---

### Task 6: Workflow réutilisable `policy.yml`

Assemble les trois contrôles en un job appelable par n'importe quel dépôt de l'organisation.

**Files:**
- Create: `.github/workflows/policy.yml`
- Create: `tests/test_policy_wiring.bats`

**Interfaces:**
- Consumes: `scripts/lib/changed-files.sh` (Task 1), `scripts/check-file-size.sh` (Task 2), `scripts/check-english.sh` (Task 4), `scripts/check-commits.sh` (Task 5).
- Produces: workflow réutilisable `nivuus/.github/.github/workflows/policy.yml@main`, sans entrée obligatoire. Le job s'appelle `policy` — ce nom devient le contexte de check requis dans la protection de branche, il ne doit plus changer.

**Point technique déterminant.** Un workflow réutilisable n'apporte pas les fichiers de son dépôt : le runner ne voit que le dépôt appelant. `policy.yml` doit donc checkouter `nivuus/.github` dans un sous-répertoire pour accéder à ses propres scripts.

Le `fetch-depth: 0` sur le dépôt appelant est indispensable : sans historique complet, `git diff origin/main...HEAD` et `git log main..HEAD` échouent.

- [ ] **Step 1: Write the failing test**

Ce test vérifie le câblage du workflow, pas son exécution sur un runner. Il empêche les régressions les plus coûteuses : un job renommé casse silencieusement la protection de branche, un `fetch-depth` oublié casse tous les contrôles.

Créer `tests/test_policy_wiring.bats` :

```bash
#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/policy.yml"
}

@test "policy workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "job id stays 'policy' so branch protection keeps matching" {
    grep -qE '^  policy:' "$WF"
}

@test "fetches full history for the diff and the commit range" {
    grep -q "fetch-depth: 0" "$WF"
}

@test "checks out the socle to reach its scripts" {
    grep -q "repository: nivuus/.github" "$WF"
}

@test "installs gawk, required by the French detector" {
    grep -q "gawk" "$WF"
}

@test "runs all three checks" {
    grep -q "check-file-size.sh" "$WF"
    grep -q "check-english.sh" "$WF"
    grep -q "check-commits.sh" "$WF"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_policy_wiring.bats`
Expected: FAIL — le premier test échoue, le fichier n'existe pas.

- [ ] **Step 3: Write minimal implementation**

Créer `.github/workflows/policy.yml` :

```yaml
name: Policy

on:
  workflow_call:

jobs:
  policy:
    name: Coding rules
    runs-on: ubuntu-latest
    steps:
      - name: Check out the calling repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Check out the shared socle
        uses: actions/checkout@v4
        with:
          repository: nivuus/.github
          ref: main
          path: .nivuus-socle

      - name: Install gawk
        run: sudo apt-get update && sudo apt-get install -y gawk

      - name: Resolve the base ref
        id: base
        run: |
          base="${{ github.event.pull_request.base.ref || github.event.repository.default_branch }}"
          git fetch -q origin "$base"
          echo "ref=origin/$base" >> "$GITHUB_OUTPUT"

      - name: List changed files
        run: |
          source .nivuus-socle/scripts/lib/changed-files.sh
          changed_files "${{ steps.base.outputs.ref }}" HEAD > changed.txt
          echo "Changed files:"
          cat changed.txt

      - name: Enforce the 500-line limit
        run: .nivuus-socle/scripts/check-file-size.sh < changed.txt

      - name: Enforce English in code
        run: .nivuus-socle/scripts/check-english.sh < changed.txt

      - name: Enforce conventional commits
        if: github.event_name == 'pull_request'
        run: .nivuus-socle/scripts/check-commits.sh "${{ steps.base.outputs.ref }}" HEAD
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_policy_wiring.bats`
Expected: PASS — 7 tests

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/policy.yml tests/test_policy_wiring.bats
git commit -m "ci: add reusable policy workflow"
```

---

### Task 7: Workflow réutilisable `security.yml`

**Files:**
- Create: `.github/workflows/security.yml`
- Create: `tests/test_security_wiring.bats`

**Interfaces:**
- Consumes: rien du socle.
- Produces: workflow réutilisable `nivuus/.github/.github/workflows/security.yml@main`. Job nommé `security` — contexte de check requis, à ne plus renommer.

gitleaks tourne sur **tous** les dépôts, publics comme privés : le secret scanning natif de GitHub n'existe pas sur les dépôts privés en plan Free, et faire dépendre la détection de secrets de la visibilité du dépôt serait exactement l'hétérogénéité qu'on supprime.

L'audit de dépendances s'adapte à ce qu'il trouve : chaque gestionnaire n'est invoqué que si son fichier de manifeste existe, ce qui rend le workflow utilisable tel quel sur un dépôt vide comme `mqtt`.

- [ ] **Step 1: Write the failing test**

Créer `tests/test_security_wiring.bats` :

```bash
#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/security.yml"
}

@test "security workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "job id stays 'security' so branch protection keeps matching" {
    grep -qE '^  security:' "$WF"
}

@test "scans for secrets with gitleaks" {
    grep -q "gitleaks" "$WF"
}

@test "audits dependencies for all three ecosystems" {
    grep -q "pip-audit" "$WF"
    grep -q "cargo audit" "$WF"
    grep -q "npm audit" "$WF"
}

@test "guards each audit behind a manifest check" {
    grep -q "requirements.txt\|pyproject.toml" "$WF"
    grep -q "Cargo.lock" "$WF"
    grep -q "package-lock.json" "$WF"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_security_wiring.bats`
Expected: FAIL — le fichier n'existe pas.

- [ ] **Step 3: Write minimal implementation**

Créer `.github/workflows/security.yml` :

```yaml
name: Security

on:
  workflow_call:

jobs:
  security:
    name: Secrets and dependencies
    runs-on: ubuntu-latest
    steps:
      - name: Check out the calling repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Scan for secrets
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ github.token }}

      - name: Audit Python dependencies
        run: |
          if [ -f requirements.txt ] || [ -f pyproject.toml ]; then
            pipx install pip-audit
            pip-audit --strict || exit 1
          else
            echo "No Python manifest, skipping."
          fi

      - name: Audit Rust dependencies
        run: |
          if [ -f Cargo.lock ]; then
            cargo install cargo-audit --locked
            cargo audit
          else
            echo "No Cargo.lock, skipping."
          fi

      - name: Audit Node dependencies
        run: |
          if [ -f package-lock.json ]; then
            npm audit --audit-level=high
          else
            echo "No package-lock.json, skipping."
          fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_security_wiring.bats`
Expected: PASS — 6 tests

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/security.yml tests/test_security_wiring.bats
git commit -m "ci: add reusable security workflow"
```

---

### Task 8: Workflow réutilisable `ci-shell.yml`

Le pilote `shell` a besoin de sa CI de langage. Cette tâche reprend le contenu de son `tests.yml` actuel et le déplace dans le socle, où il devient réutilisable.

**Files:**
- Create: `.github/workflows/ci-shell.yml`
- Create: `tests/test_ci_shell_wiring.bats`

**Interfaces:**
- Consumes: rien du socle.
- Produces: workflow réutilisable avec deux entrées optionnelles :
  - `test-dirs` (string, défaut `tests/unit tests/performance`) — répertoires bats à exécuter, séparés par des espaces ;
  - `shellcheck-paths` (string, défaut `.`) — racine du scan shellcheck.

Le job s'appelle `shell` et n'est **pas** un check requis dans la protection de branche : seuls `policy` et `security` le sont, pour que le socle reste applicable à un dépôt sans code.

- [ ] **Step 1: Write the failing test**

Créer `tests/test_ci_shell_wiring.bats` :

```bash
#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/ci-shell.yml"
}

@test "ci-shell workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "exposes overridable test directories" {
    grep -q "test-dirs:" "$WF"
}

@test "exposes an overridable shellcheck root" {
    grep -q "shellcheck-paths:" "$WF"
}

@test "runs shellcheck and bats" {
    grep -q "shellcheck" "$WF"
    grep -q "bats" "$WF"
}

@test "installs zsh, required by the shell test suite" {
    grep -q "zsh" "$WF"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_ci_shell_wiring.bats`
Expected: FAIL — le fichier n'existe pas.

- [ ] **Step 3: Write minimal implementation**

Créer `.github/workflows/ci-shell.yml` :

```yaml
name: CI Shell

on:
  workflow_call:
    inputs:
      test-dirs:
        description: Space-separated bats directories to run
        type: string
        default: tests/unit tests/performance
      shellcheck-paths:
        description: Root directory to scan with shellcheck
        type: string
        default: "."

jobs:
  shell:
    name: Shell checks
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install toolchain
        run: |
          sudo apt-get update
          sudo apt-get install -y zsh bats shellcheck

      - name: Run shellcheck
        run: |
          mapfile -t files < <(
            find "${{ inputs.shellcheck-paths }}" \
              -path ./.git -prune -o \
              -type f \( -name '*.sh' -o -name '*.bash' \) -print
          )
          if [ "${#files[@]}" -eq 0 ]; then
            echo "No shell scripts found, skipping."
            exit 0
          fi
          shellcheck -S warning "${files[@]}"

      - name: Run bats suites
        env:
          NIVUUS_SHELL_DIR: ${{ github.workspace }}
        run: |
          for dir in ${{ inputs.test-dirs }}; do
            if [ -d "$dir" ]; then
              echo "Running $dir"
              bats "$dir"
            else
              echo "No $dir, skipping."
            fi
          done
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_ci_shell_wiring.bats`
Expected: PASS — 6 tests

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci-shell.yml tests/test_ci_shell_wiring.bats
git commit -m "ci: add reusable shell workflow"
```

---

### Task 9: Fichiers de santé communs

Ces fichiers, placés à la racine de `nivuus/.github`, s'appliquent automatiquement à tous les dépôts **publics** de l'organisation. Les trois dépôts privés en recevront une copie lors du second plan.

**Files:**
- Create: `CONTRIBUTING.md`
- Create: `SECURITY.md`
- Create: `PULL_REQUEST_TEMPLATE.md`
- Create: `dependabot.yml`
- Create: `tests/test_health_files.bats`

**Interfaces:**
- Consumes: rien.
- Produces: fichiers de santé référencés par le second plan pour les dépôts privés.

Ces documents s'adressent aux contributeurs, pas au code : ils sont donc rédigés en **français**, conformément à la règle « docs produit en français » du spec.

- [ ] **Step 1: Write the failing test**

Créer `tests/test_health_files.bats` :

```bash
#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/.."
}

@test "all health files are present" {
    [ -f "$ROOT/CONTRIBUTING.md" ]
    [ -f "$ROOT/SECURITY.md" ]
    [ -f "$ROOT/PULL_REQUEST_TEMPLATE.md" ]
    [ -f "$ROOT/dependabot.yml" ]
}

@test "CONTRIBUTING states the three coding rules" {
    grep -q "500" "$ROOT/CONTRIBUTING.md"
    grep -qi "anglais" "$ROOT/CONTRIBUTING.md"
    grep -qi "conventional commits" "$ROOT/CONTRIBUTING.md"
}

@test "CONTRIBUTING documents the escape hatch" {
    grep -q "policy: allow-fr" "$ROOT/CONTRIBUTING.md"
}

@test "SECURITY gives a reporting address" {
    grep -q "@" "$ROOT/SECURITY.md"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_health_files.bats`
Expected: FAIL — aucun des fichiers n'existe.

- [ ] **Step 3: Write the files**

`CONTRIBUTING.md` :

```markdown
# Contribuer aux projets Nivuus

## Workflow

La branche principale s'appelle `main` et n'accepte aucun push direct.
Toute modification passe par une pull request dont les checks `policy` et
`security` doivent être verts. Le merge se fait en squash, et la branche est
supprimée automatiquement.

## Règles de codage

**Anglais dans le code.** Les identifiants, les commentaires, les docstrings,
les messages de commit et les noms de branches sont en anglais. Les chaînes
affichées à l'utilisateur, les README, les CHANGELOG et le contenu de `docs/`
restent en français.

Si une ligne déclenche à tort le contrôle — un nom propre, un terme métier
français sans équivalent, un identifiant de protocole — ajoutez
`policy: allow-fr` en fin de ligne.

**500 lignes maximum par fichier source.** La règle vise le code de
production ; les fichiers de test et les fichiers générés en sont exemptés.
Un fichier qui dépasse la limite signale généralement une responsabilité mal
découpée.

**Conventional Commits.** Format `<type>(<portée>)!: <sujet en anglais>`.
Types acceptés : `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`,
`perf`, `build`, `style`, `revert`. Le format conditionne la génération du
CHANGELOG et le calcul de version, il est donc bloquant.

## Portée des contrôles

Les contrôles ne s'appliquent qu'aux fichiers ajoutés ou modifiés dans la
pull request. Le code existant qui ne respecte pas encore ces règles n'est
pas signalé tant qu'on n'y touche pas.
```

`SECURITY.md` :

```markdown
# Signaler une vulnérabilité

Merci de ne pas ouvrir d'issue publique pour une faille de sécurité.

Écrivez à **security@nivuus.com** avec une description du problème, les
étapes de reproduction et, si vous en avez, l'impact estimé. Nous accusons
réception sous 72 heures.

## Versions supportées

Seule la dernière version publiée de chaque projet reçoit des correctifs de
sécurité.
```

`PULL_REQUEST_TEMPLATE.md` :

```markdown
## Ce que fait cette PR

<!-- Une à trois phrases. Le pourquoi compte plus que le comment. -->

## Comment le vérifier

<!-- Commandes à lancer, ou parcours à suivre dans l'interface. -->

## Points d'attention

<!-- Choix discutables, dette assumée, effets de bord. Supprimez si rien. -->
```

`dependabot.yml` (gabarit à copier dans `.github/dependabot.yml` de chaque dépôt, en ne gardant que les écosystèmes présents) :

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
    commit-message:
      prefix: "ci"

  - package-ecosystem: pip
    directory: "/"
    schedule:
      interval: weekly
    commit-message:
      prefix: "chore"

  - package-ecosystem: cargo
    directory: "/"
    schedule:
      interval: weekly
    commit-message:
      prefix: "chore"

  - package-ecosystem: npm
    directory: "/"
    schedule:
      interval: weekly
    commit-message:
      prefix: "chore"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_health_files.bats`
Expected: PASS — 4 tests

- [ ] **Step 5: Commit**

```bash
git add CONTRIBUTING.md SECURITY.md PULL_REQUEST_TEMPLATE.md dependabot.yml tests/test_health_files.bats
git commit -m "docs: add shared community health files"
```

---

### Task 10: Configuration serveur — `apply-org-config.sh`

La protection de branche, le secret scanning et la stratégie de merge ne peuvent pas vivre dans un fichier versionné. Ce script est leur trace écrite : idempotent, rejouable, lisible.

**Files:**
- Create: `scripts/apply-org-config.sh`
- Test: `tests/test_apply_org_config.bats`

**Interfaces:**
- Consumes: rien du socle.
- Produces: `scripts/apply-org-config.sh [--dry-run] <repo> [<repo>...]` où `<repo>` est de la forme `nivuus/shell`. Sortie 0 si tout a été appliqué, 1 si un appel a échoué.
  - Variable d'environnement `GH_BIN` (défaut `gh`) — permet d'injecter un double de test.
  - `--dry-run` affiche chaque appel sans l'exécuter.

**Deux pièges à connaître.**

*Le nom des contextes de check.* Quand un dépôt appelle un workflow réutilisable, GitHub nomme le check `<id du job appelant> / <nom du job appelé>`. Avec l'appelant `policy:` et le job `name: Coding rules`, le contexte est donc `policy / Coding rules`, pas `policy`. Une erreur ici produit une protection qui attend un check qui n'arrive jamais, et bloque tous les merges. Les valeurs retenues ici sont vérifiées empiriquement en Task 15 avant l'activation.

*Les dépôts privés.* En plan Free, l'API renvoie `403 Upgrade to GitHub Pro` sur la protection de branche d'un dépôt privé. Le script détecte la visibilité et saute proprement l'étape avec un avertissement, au lieu d'échouer.

- [ ] **Step 1: Write the failing test**

Créer `tests/test_apply_org_config.bats` :

```bash
#!/usr/bin/env bats

setup() {
    SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"
    WORK="$(mktemp -d)"
    cd "$WORK" || return 1

    # A gh double: logs its arguments, answers visibility queries.
    cat > gh <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
if [ "$*" = "${GH_VISIBILITY_QUERY}" ]; then
    printf '%s\n' "${GH_VISIBILITY:-public}"
fi
exit 0
STUB
    chmod +x gh
    export GH_BIN="$WORK/gh"
    export GH_LOG="$WORK/calls.log"
    : > "$GH_LOG"
}

teardown() {
    [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

@test "requires at least one repository" {
    run "$SCRIPTS/apply-org-config.sh"
    [ "$status" -ne 0 ]
}

@test "dry-run performs no write call" {
    run "$SCRIPTS/apply-org-config.sh" --dry-run nivuus/shell
    [ "$status" -eq 0 ]
    run grep -c "PUT\|PATCH" "$GH_LOG"
    [ "$output" = "0" ]
}

@test "sets the merge strategy on a public repo" {
    export GH_VISIBILITY=public
    run "$SCRIPTS/apply-org-config.sh" nivuus/shell
    [ "$status" -eq 0 ]
    grep -q "delete_branch_on_merge=true" "$GH_LOG"
    grep -q "allow_squash_merge=true" "$GH_LOG"
    grep -q "allow_merge_commit=false" "$GH_LOG"
}

@test "protects the main branch of a public repo" {
    export GH_VISIBILITY=public
    run "$SCRIPTS/apply-org-config.sh" nivuus/shell
    [ "$status" -eq 0 ]
    grep -q "branches/main/protection" "$GH_LOG"
}

@test "skips branch protection on a private repo" {
    export GH_VISIBILITY=private
    run "$SCRIPTS/apply-org-config.sh" nivuus/desk
    [ "$status" -eq 0 ]
    run grep -c "branches/main/protection" "$GH_LOG"
    [ "$output" = "0" ]
}

@test "warns when it skips a private repo" {
    export GH_VISIBILITY=private
    run "$SCRIPTS/apply-org-config.sh" nivuus/desk
    [[ "$output" == *"WARNING"* ]]
}

@test "enables dependabot alerts on every repo" {
    export GH_VISIBILITY=private
    run "$SCRIPTS/apply-org-config.sh" nivuus/desk
    [ "$status" -eq 0 ]
    grep -q "vulnerability-alerts" "$GH_LOG"
}

@test "handles several repositories in one run" {
    export GH_VISIBILITY=public
    run "$SCRIPTS/apply-org-config.sh" nivuus/shell nivuus/mqtt
    [ "$status" -eq 0 ]
    grep -q "nivuus/shell" "$GH_LOG"
    grep -q "nivuus/mqtt" "$GH_LOG"
}
```

Note : le double de `gh` répond à la requête de visibilité en comparant ses arguments à `$GH_VISIBILITY_QUERY`. Le script doit donc exporter cette variable avant d'appeler `gh` pour la visibilité — voir l'implémentation ci-dessous.

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_apply_org_config.bats`
Expected: FAIL — `apply-org-config.sh: No such file or directory`

- [ ] **Step 3: Write minimal implementation**

Créer `scripts/apply-org-config.sh` (`chmod +x`) :

```bash
#!/usr/bin/env bash
# Apply the shared Nivuus server-side configuration to one or more repos.
# Usage: apply-org-config.sh [--dry-run] <owner/repo>...
set -uo pipefail

GH_BIN="${GH_BIN:-gh}"
DRY_RUN=0

# Required status check contexts. A reusable workflow is reported as
# "<caller job id> / <called job name>", not just the job id.
readonly CHECK_POLICY="policy / Coding rules"
readonly CHECK_SECURITY="security / Secrets and dependencies"

run_gh() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'DRY-RUN: %s %s\n' "$GH_BIN" "$*"
        return 0
    fi
    "$GH_BIN" "$@"
}

visibility_of() {
    local repo="$1"
    export GH_VISIBILITY_QUERY="api repos/${repo} --jq .visibility"
    "$GH_BIN" api "repos/${repo}" --jq .visibility
}

apply_merge_strategy() {
    local repo="$1"
    run_gh api -X PATCH "repos/${repo}" \
        -F delete_branch_on_merge=true \
        -F allow_squash_merge=true \
        -F allow_merge_commit=false \
        -F allow_rebase_merge=false
}

apply_secret_scanning() {
    local repo="$1"
    run_gh api -X PATCH "repos/${repo}" \
        -f 'security_and_analysis[secret_scanning][status]=enabled' \
        -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
}

apply_dependabot() {
    local repo="$1"
    run_gh api -X PUT "repos/${repo}/vulnerability-alerts"
    run_gh api -X PUT "repos/${repo}/automated-security-fixes"
}

apply_branch_protection() {
    local repo="$1"
    local payload
    payload=$(cat <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["${CHECK_POLICY}", "${CHECK_SECURITY}"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
)
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'DRY-RUN: %s api -X PUT repos/%s/branches/main/protection\n' "$GH_BIN" "$repo"
        return 0
    fi
    printf '%s' "$payload" \
        | "$GH_BIN" api -X PUT "repos/${repo}/branches/main/protection" --input -
}

apply_repo() {
    local repo="$1" vis rc=0

    printf '\n== %s ==\n' "$repo"
    vis="$(visibility_of "$repo")" || vis="unknown"

    apply_merge_strategy "$repo" || rc=1
    apply_dependabot "$repo" || rc=1

    if [ "$vis" = "public" ]; then
        apply_secret_scanning "$repo" || rc=1
        apply_branch_protection "$repo" || rc=1
    else
        printf 'WARNING: %s is %s. Branch protection and secret scanning need a paid plan; skipping.\n' \
            "$repo" "$vis"
    fi

    return "$rc"
}

main() {
    local rc=0 repo

    while [ "$#" -gt 0 ] && [ "${1:0:2}" = "--" ]; do
        case "$1" in
            --dry-run) DRY_RUN=1; shift ;;
            *) printf 'Unknown option: %s\n' "$1"; return 2 ;;
        esac
    done

    if [ "$#" -eq 0 ]; then
        printf 'Usage: apply-org-config.sh [--dry-run] <owner/repo>...\n'
        return 2
    fi

    for repo in "$@"; do
        apply_repo "$repo" || rc=1
    done

    return "$rc"
}

main "$@"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_apply_org_config.bats`
Expected: PASS — 8 tests

- [ ] **Step 5: Commit**

```bash
git add scripts/apply-org-config.sh tests/test_apply_org_config.bats
git commit -m "feat: add idempotent org configuration script"
```

---

### Task 11: Le socle se soumet à ses propres règles

`nivuus/.github` est un dépôt public comme les autres : il doit consommer son propre socle. C'est aussi la première validation réelle du câblage `workflow_call`.

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/self-test.yml`
- Create: `.github/dependabot.yml`

**Interfaces:**
- Consumes: `policy.yml` (Task 6), `security.yml` (Task 7).
- Produces: rien pour les tâches suivantes.

Un workflow séparé, `self-test.yml`, exécute la suite bats du socle. Il ne peut pas passer par `ci-shell.yml` : les tests du socle vivent à la racine `tests/`, pas sous `tests/unit/`, et surtout un socle qui se testerait via son propre workflow réutilisable rendrait toute erreur indétectable.

- [ ] **Step 1: Write the workflows**

Créer `.github/workflows/ci.yml` :

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  policy:
    uses: nivuus/.github/.github/workflows/policy.yml@main
  security:
    uses: nivuus/.github/.github/workflows/security.yml@main
```

Créer `.github/workflows/self-test.yml` :

```yaml
name: Self test

on:
  pull_request:
  push:
    branches: [main]

jobs:
  bats:
    name: Socle test suite
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install toolchain
        run: |
          sudo apt-get update
          sudo apt-get install -y bats gawk shellcheck
      - name: Run shellcheck on the socle scripts
        run: shellcheck -S warning scripts/*.sh scripts/lib/*.sh
      - name: Run the test suite
        run: bats tests/
```

Créer `.github/dependabot.yml` (seul l'écosystème `github-actions` s'applique ici) :

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
    commit-message:
      prefix: "ci"
```

- [ ] **Step 2: Run the full suite locally**

Run: `bats tests/`
Expected: PASS — toutes les suites des Tasks 1 à 10.

Run: `shellcheck -S warning scripts/*.sh scripts/lib/*.sh`
Expected: aucune sortie.

- [ ] **Step 3: Commit and open the first pull request**

```bash
git add .github/workflows/ci.yml .github/workflows/self-test.yml .github/dependabot.yml
git commit -m "ci: run the socle against its own rules"
git push -u origin HEAD
gh pr create --repo nivuus/.github --fill
```

- [ ] **Step 4: Verify the workflows actually run on GitHub**

Run: `gh pr checks --repo nivuus/.github --watch`
Expected: les jobs `policy`, `security` et `bats` apparaissent et passent au vert.

Si `policy` échoue sur le checkout du socle, la cause la plus probable est que la branche `main` de `nivuus/.github` ne contient pas encore les workflows — ils n'existent que sur la branche de la PR. Dans ce cas, merger d'abord cette PR en désactivant temporairement la protection, puisqu'elle n'est pas encore activée à ce stade du plan.

- [ ] **Step 5: Record the real check names**

C'est l'information dont la Task 14 a besoin et qu'aucune documentation ne garantit.

```bash
gh api "repos/nivuus/.github/commits/$(git rev-parse HEAD)/check-runs" \
  --jq '.check_runs[].name'
```

Comparer la sortie aux constantes `CHECK_POLICY` et `CHECK_SECURITY` de `scripts/apply-org-config.sh`. Si elles diffèrent, corriger le script, relancer `bats tests/test_apply_org_config.bats`, et commiter :

```bash
git commit -am "fix: align required check contexts with the names GitHub reports"
```

---

### Task 12: Pilote `shell` — renommage de `master` en `main`

À partir d'ici, on travaille dans le dépôt `nivuus/shell`, cloné en local dans `packages/shell`.

**Files:**
- Modify: `.github/workflows/tests.yml:5-7`
- Modify: `.github/workflows/release.yml:240-243`

**Interfaces:**
- Consumes: rien.
- Produces: branche par défaut `main` sur `nivuus/shell`, prérequis des Tasks 13 et 14.

- [ ] **Step 1: Rename the branch on GitHub**

```bash
gh api -X POST repos/nivuus/shell/branches/master/rename -f new_name=main
```

GitHub redirige automatiquement les anciennes références et met à jour les pull requests ouvertes.

- [ ] **Step 2: Realign the local clone**

```bash
cd packages/shell
git branch -m master main
git fetch origin
git branch -u origin/main main
git remote set-head origin -a
```

- [ ] **Step 3: Verify no branch is left behind**

Run: `git rev-parse --abbrev-ref origin/HEAD`
Expected: `origin/main`

Run: `gh api repos/nivuus/shell --jq .default_branch`
Expected: `main`

- [ ] **Step 4: Update the hardcoded references**

Dans `.github/workflows/tests.yml`, remplacer les deux listes de branches :

```yaml
on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]
```

Dans `.github/workflows/release.yml`, supprimer entièrement l'étape `Push version updates to master` (lignes 240-243). Le remplacement du mécanisme est l'objet de la Task 13 ; ici on retire seulement ce qui deviendrait invalide.

- [ ] **Step 5: Commit**

```bash
git checkout -b chore/rename-default-branch
git add .github/workflows/tests.yml .github/workflows/release.yml
git commit -m "ci: rename default branch to main"
git push -u origin HEAD
```

---

### Task 13: Pilote `shell` — versionnement dérivé du tag

Le workflow de release commite aujourd'hui un bump de version sur la branche principale. Sous protection, ce push serait rejeté et chaque release échouerait. La version doit désormais venir du tag.

**Files:**
- Modify: `.github/workflows/release.yml:84-140`
- Create: `tests/unit/test_version_source.bats`

**Interfaces:**
- Consumes: rien.
- Produces: `scripts/version.sh` exposant `current_version()` — lit le dernier tag `v*` et renvoie la version sans le préfixe `v`, ou `0.0.0` si aucun tag n'existe.

Le principe : `package.json` et `install.sh` restent mis à jour **dans l'espace de travail du runner**, pour que les artefacts publiés portent le bon numéro, mais rien n'est commité ni poussé. La source de vérité devient le tag git.

- [ ] **Step 1: Write the failing test**

Créer `tests/unit/test_version_source.bats` :

```bash
#!/usr/bin/env bats

setup() {
    SCRIPTS="${BATS_TEST_DIRNAME}/../../scripts"
    WORK="$(mktemp -d)"
    cd "$WORK" || return 1
    git init -q -b main .
    git config user.email "test@nivuus.local"
    git config user.name "Test"
    git commit -q --allow-empty -m "chore: initial commit"
}

teardown() {
    [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

@test "falls back to 0.0.0 with no tag" {
    run bash -c "source '$SCRIPTS/version.sh'; current_version"
    [ "$status" -eq 0 ]
    [ "$output" = "0.0.0" ]
}

@test "reads the latest version tag" {
    git tag -a v3.0.0 -m "Release v3.0.0"
    run bash -c "source '$SCRIPTS/version.sh'; current_version"
    [ "$status" -eq 0 ]
    [ "$output" = "3.0.0" ]
}

@test "picks the highest version, not the most recent tag" {
    git tag -a v3.0.0 -m "Release v3.0.0"
    git commit -q --allow-empty -m "chore: another commit"
    git tag -a v3.1.0 -m "Release v3.1.0"
    git commit -q --allow-empty -m "chore: yet another"
    git tag -a v3.0.1 -m "Release v3.0.1"

    run bash -c "source '$SCRIPTS/version.sh'; current_version"
    [ "$status" -eq 0 ]
    [ "$output" = "3.1.0" ]
}

@test "ignores non-version tags" {
    git tag -a nightly -m "Nightly"
    run bash -c "source '$SCRIPTS/version.sh'; current_version"
    [ "$status" -eq 0 ]
    [ "$output" = "0.0.0" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/unit/test_version_source.bats`
Expected: FAIL — `version.sh: No such file or directory`

- [ ] **Step 3: Write minimal implementation**

Créer `scripts/version.sh` :

```bash
#!/usr/bin/env bash
# Derive the current version from git tags.

current_version() {
    local tag
    tag="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname | head -n 1)"
    if [ -z "$tag" ]; then
        printf '0.0.0'
        return 0
    fi
    printf '%s' "${tag#v}"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/unit/test_version_source.bats`
Expected: PASS — 4 tests

- [ ] **Step 5: Rewire the release workflow**

Dans `.github/workflows/release.yml`, remplacer l'étape `Calculate new version` (lignes 84-116) par :

```yaml
      - name: Calculate new version
        id: version
        run: |
          source scripts/version.sh
          CURRENT_VERSION="$(current_version)"
          echo "Current version: $CURRENT_VERSION"

          IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
          case "${{ github.event.inputs.bump_type }}" in
            major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
            minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
            patch) PATCH=$((PATCH + 1)) ;;
            *) echo "Unknown bump type"; exit 1 ;;
          esac

          NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
          echo "New version: $NEW_VERSION"
          echo "version=$NEW_VERSION" >> "$GITHUB_OUTPUT"
          echo "NEW_VERSION=$NEW_VERSION" >> "$GITHUB_ENV"
```

L'étape de checkout du job de release doit récupérer les tags, sans quoi `current_version` renverra toujours `0.0.0` :

```yaml
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
```

Les étapes `Update version in package.json` et `Update version in install.sh` (lignes 126-140) sont **conservées telles quelles** : elles alimentent les artefacts de la release. Seule l'étape `Commit version updates` (lignes 223-231) est supprimée, avec celle de push déjà retirée en Task 12.

- [ ] **Step 6: Verify no push to main remains**

Run: `grep -n "git push origin HEAD\|git commit" .github/workflows/release.yml`
Expected: seule la création de tag subsiste (`git push origin "v..."`), aucun `git commit` ni push vers une branche.

- [ ] **Step 7: Commit**

```bash
git add scripts/version.sh tests/unit/test_version_source.bats .github/workflows/release.yml
git commit -m "ci: derive release version from git tags"
```

---

### Task 14: Pilote `shell` — branchement sur le socle

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/dependabot.yml`
- Delete: `.github/workflows/tests.yml`

**Interfaces:**
- Consumes: `policy.yml` (Task 6), `security.yml` (Task 7), `ci-shell.yml` (Task 8).
- Produces: une pull request sur `nivuus/shell` servant de terrain au point de contrôle de la Task 15.

`tests.yml` est supprimé : son contenu vit désormais dans `ci-shell.yml`. Le conserver ferait tourner la même suite deux fois et donnerait deux sources de vérité à maintenir.

- [ ] **Step 1: Create the caller workflow**

Créer `.github/workflows/ci.yml` :

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  policy:
    uses: nivuus/.github/.github/workflows/policy.yml@main
  security:
    uses: nivuus/.github/.github/workflows/security.yml@main
  shell:
    uses: nivuus/.github/.github/workflows/ci-shell.yml@main
    with:
      test-dirs: tests/unit tests/performance
      shellcheck-paths: "."
```

- [ ] **Step 2: Create the dependabot configuration**

Créer `.github/dependabot.yml` :

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
    commit-message:
      prefix: "ci"

  - package-ecosystem: npm
    directory: "/"
    schedule:
      interval: weekly
    commit-message:
      prefix: "chore"
```

- [ ] **Step 3: Remove the superseded workflow**

```bash
git rm .github/workflows/tests.yml
```

- [ ] **Step 4: Commit and open the pull request**

```bash
git add .github/workflows/ci.yml .github/dependabot.yml
git commit -m "ci: adopt the shared nivuus socle"
git push -u origin HEAD
gh pr create --repo nivuus/shell --fill
```

- [ ] **Step 5: Watch the checks**

Run: `gh pr checks --repo nivuus/shell --watch`
Expected: `policy`, `security` et `shell` remontent leurs résultats.

Ne pas merger encore : la Task 15 exploite précisément cette exécution.

---

### Task 15: Point de contrôle — mesurer avant de généraliser

C'est l'étape qui justifie d'avoir choisi un dépôt pilote. `shell` contient 7 fichiers avec du français et 1 fichier de plus de 500 lignes : si l'heuristique produit du bruit, il vaut mieux le découvrir ici que sur huit dépôts.

**Files:**
- Modify (selon les résultats) : `scripts/lib/french-words.txt`, `scripts/lib/english.awk`, `scripts/apply-org-config.sh` dans `nivuus/.github`

**Interfaces:**
- Consumes: la pull request ouverte en Task 14.
- Produces: le verdict qui conditionne l'écriture du second plan.

- [ ] **Step 1: Measure the false-positive rate on real code**

Depuis un clone à jour de `nivuus/shell`, faire tourner le contrôle sur **tout** le dépôt, pas seulement sur le diff :

```bash
cd packages/shell
find . -path ./.git -prune -o -type f \
  \( -name '*.sh' -o -name '*.zsh' \) -print \
  | /chemin/vers/org-profile/scripts/check-english.sh > /tmp/english-report.txt
wc -l /tmp/english-report.txt
```

- [ ] **Step 2: Classify every hit**

Pour chaque ligne du rapport, trancher : vrai positif (du français dans du code) ou faux positif (une chaîne d'interface mal découpée, un mot anglais présent à tort dans la liste, un nom propre).

Critère de décision, à appliquer sans indulgence :

- **moins de 10 % de faux positifs** — l'heuristique est utilisable, passer à l'étape 4 ;
- **entre 10 et 30 %** — retirer de `french-words.txt` les mots responsables, réexécuter, reclasser ;
- **plus de 30 %** — le problème est structurel, pas lexical. Restreindre le contrôle aux seuls commentaires en désactivant l'analyse des identifiants dans `english.awk`, et le consigner comme limite dans `CONTRIBUTING.md`.

- [ ] **Step 3: Apply the corrections to the socle**

Toute modification de `french-words.txt` ou de `english.awk` doit conserver la suite verte :

Run: `bats tests/test_english_awk.bats tests/test_check_english.bats`
Expected: PASS

Commiter dans `nivuus/.github` via une pull request, puisque le socle est désormais soumis à ses propres règles.

- [ ] **Step 4: Confirm the required check names**

```bash
gh api "repos/nivuus/shell/commits/$(git rev-parse HEAD)/check-runs" \
  --jq '.check_runs[].name'
```

Ces noms doivent correspondre exactement aux constantes `CHECK_POLICY` et `CHECK_SECURITY` de `apply-org-config.sh`. C'est la dernière occasion de les corriger avant que la protection ne devienne bloquante.

- [ ] **Step 5: Merge, then enable protection**

L'ordre compte : activer la protection avant de merger bloquerait la pull request qui contient la CI que la protection exige.

```bash
gh pr merge --repo nivuus/shell --squash --delete-branch
cd ../org-profile
./scripts/apply-org-config.sh --dry-run nivuus/shell
./scripts/apply-org-config.sh nivuus/shell
```

- [ ] **Step 6: Verify the protection is really in place**

```bash
gh api repos/nivuus/shell/branches/main/protection \
  --jq '{checks: .required_status_checks.contexts,
         admins: .enforce_admins.enabled,
         reviews: .required_pull_request_reviews.required_approving_review_count,
         linear: .required_linear_history.enabled,
         force: .allow_force_pushes.enabled}'
```

Expected:
```json
{"checks": ["policy / Coding rules", "security / Secrets and dependencies"],
 "admins": true, "reviews": 0, "linear": true, "force": false}
```

- [ ] **Step 7: Prove that direct push is now refused**

```bash
git checkout main && git pull
git commit --allow-empty -m "chore: verify protection"
git push origin main
```

Expected: le push est **rejeté** (`protected branch hook declined`). Nettoyer ensuite :

```bash
git reset --hard origin/main
```

Si le push réussit, la protection n'est pas active : reprendre à l'étape 5.

- [ ] **Step 8: Apply the same configuration to the socle repository**

```bash
./scripts/apply-org-config.sh nivuus/.github
```

- [ ] **Step 9: Record the outcome**

Écrire dans `docs/superpowers/plans/2026-08-26-socle-uniformisation-nivuus-resultats.md` : le taux de faux positifs mesuré, les mots retirés de la liste, les noms de checks réels, et toute correction apportée au socle. Ce document est l'entrée du second plan.

```bash
git add docs/superpowers/plans/2026-08-26-socle-uniformisation-nivuus-resultats.md
git commit -m "docs: record pilot results for the shell repository"
```

---

## Ce qui reste après ce plan

Le second plan couvrira les étapes 4 et 5 du § 8 du spec :

- extension aux quatre autres dépôts publics (`installer`, `mqtt`, `marketplace`, et `design` s'il devient public) ;
- extension aux trois dépôts privés (`desk`, `home-stock`, `design`), avec copie locale des fichiers de santé et renommage de `home-stock` en `main` ;
- workflows `ci-python.yml`, `ci-rust.yml` et `ci-node.yml`, absents ici faute de dépôt pilote qui en ait besoin ;
- activation de CodeQL sur `installer`.
