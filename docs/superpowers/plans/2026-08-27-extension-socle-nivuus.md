# Extension du socle aux six dépôts restants — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Étendre le socle partagé aux six dépôts restants de l'organisation, en ajoutant les trois workflows de langage qui leur manquent.

**Architecture:** Les workflows `ci-python`, `ci-rust` et `ci-node` rejoignent le socle sur le modèle de `ci-shell`, avec des entrées optionnelles et un comportement inoffensif sur un dépôt vide. Chaque dépôt consommateur reçoit ensuite son `ci.yml`, son `dependabot.yml`, et pour les publics la configuration serveur.

**Tech Stack:** GitHub Actions (`workflow_call`), bats-core 1.11, ruff, pytest, cargo, npm, gawk, shellcheck.

**Spec:** `docs/superpowers/specs/2026-08-26-uniformisation-org-nivuus-design.md` — étapes 4 et 5 du § 8.

**Plan précédent:** `docs/superpowers/plans/2026-08-26-socle-uniformisation-nivuus.md`, exécuté. Le socle et le pilote `shell` sont en place et protégés.

## Global Constraints

- Code, identifiants et commentaires en **anglais** ; chaînes destinées à l'utilisateur, README, CHANGELOG et `docs/` en **français**.
- Limite de **500 lignes** par fichier source ; fichiers de test exemptés.
- Échappements : `policy: allow-fr` (ligne, dans un commentaire), `policy: allow-fr-file` et `policy: allow-long-file` (fichier).
- Commits : **Conventional Commits**, sujet en anglais. Types : `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`, `perf`, `build`, `style`, `revert`.
- Le contrôle « anglais » ne juge que les **lignes ajoutées** ; la règle de taille juge le fichier entier.
- Jamais d'expression `${{ }}` dans un bloc `run:` — elle transite par `env:`.
- Contextes de checks requis, exacts : `policy / Coding rules` et `security / Secrets and dependencies`.
- Les identifiants de job appelants doivent être `policy` et `security`.
- Le socle s'applique ses propres règles : toute modification y passe par une pull request.

## État de départ, mesuré le 27 août 2026

| Dépôt | Visibilité | Branche | Code présent | Manifestes |
|---|---|---|---|---|
| installer | public | main | 40 `.py`, 28 `.sh` | **aucun manifeste Python** |
| mqtt | public | main | 74 `.ts`, 8 `.sh` | `package.json` |
| marketplace | public | main | 12 `.py`, 7 `.ts` | `hacs.json`, `frontend/package.json` |
| desk | privé | main | 159 `.rs`, 82 `.ts`, 16 `.sh` | `Cargo.toml`, 3 × `package.json` |
| home-stock | privé | **master** | 36 `.py` | `hacs.json`, `pytest.ini` |
| design | privé | main | aucun code | aucun |

Audit gitleaks du 27 août : les six sont propres à l'exception d'`installer`, dont l'unique détection est un placeholder de documentation (`YOUR_TOKEN`).

## File Structure

| Fichier | Responsabilité |
|---|---|
| `.github/workflows/ci-python.yml` | Workflow réutilisable : ruff, pytest |
| `.github/workflows/ci-rust.yml` | Workflow réutilisable : fmt, clippy, test |
| `.github/workflows/ci-node.yml` | Workflow réutilisable : typecheck, lint, test |
| `tests/test_ci_python_wiring.bats` | Câblage du workflow Python |
| `tests/test_ci_rust_wiring.bats` | Câblage du workflow Rust |
| `tests/test_ci_node_wiring.bats` | Câblage du workflow Node |
| `.gitleaks.toml` (dans `installer`) | Allowlist du placeholder de documentation |
| `.github/workflows/ci.yml` (× 6) | Appelant, un par dépôt consommateur |
| `.github/dependabot.yml` (× 6) | Configuration Dependabot, un par dépôt |

---

### Task 1: Workflow réutilisable `ci-python.yml`

**Files:**
- Create: `.github/workflows/ci-python.yml`
- Test: `tests/test_ci_python_wiring.bats`

**Interfaces:**
- Consumes: rien du socle.
- Produces: workflow réutilisable avec trois entrées optionnelles :
  - `python-version` (string, défaut `3.12`)
  - `test-paths` (string, défaut `tests`) — répertoires ou fichiers pytest, séparés par des espaces
  - `lint-paths` (string, défaut `.`) — racine du scan ruff

Job nommé `python`. Il n'est **pas** un check requis : seuls `policy` et `security` le sont, pour que le socle reste applicable à un dépôt sans code.

**Deux contraintes tirées de l'état réel des dépôts.** `installer` a 40 fichiers Python et **aucun manifeste** : le workflow doit fonctionner sans `requirements.txt` ni `pyproject.toml`, donc l'installation des dépendances est conditionnelle. Et `marketplace` n'a pas de répertoire `tests` : une absence de tests doit produire un saut explicite, pas un échec.

- [ ] **Step 1: Write the failing test**

Créer `tests/test_ci_python_wiring.bats` :

```bash
#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/ci-python.yml"
}

@test "ci-python workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "exposes an overridable python version" {
    grep -q "python-version:" "$WF"
}

@test "exposes overridable test and lint paths" {
    grep -q "test-paths:" "$WF"
    grep -q "lint-paths:" "$WF"
}

@test "runs ruff and pytest" {
    grep -q "ruff" "$WF"
    grep -q "pytest" "$WF"
}

# installer has 40 Python files and no manifest at all; a hard dependency
# install would fail there.
@test "installs dependencies only when a manifest exists" {
    grep -q "requirements.txt" "$WF"
    grep -q "pyproject.toml" "$WF"
}

# marketplace has Python files but no tests directory.
@test "skips cleanly when there is nothing to test" {
    grep -qi "skipping" "$WF"
}

@test "passes github expressions through env, never into run blocks" {
    run grep -nE '^ +run:.*\$\{\{' "$WF"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_ci_python_wiring.bats`
Expected: FAIL — le fichier n'existe pas.

- [ ] **Step 3: Write minimal implementation**

Créer `.github/workflows/ci-python.yml` :

```yaml
name: CI Python

on:
  workflow_call:
    inputs:
      python-version:
        description: Python version to run against
        type: string
        default: "3.12"
      test-paths:
        description: Space-separated pytest targets
        type: string
        default: tests
      lint-paths:
        description: Root directory to scan with ruff
        type: string
        default: "."

jobs:
  python:
    name: Python checks
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: ${{ inputs.python-version }}

      - name: Install dependencies when a manifest exists
        run: |
          python -m pip install --upgrade pip
          if [ -f requirements.txt ]; then
            pip install -r requirements.txt
          elif [ -f pyproject.toml ]; then
            pip install .
          else
            echo "No Python manifest, skipping dependency install."
          fi
          pip install ruff pytest

      - name: Run ruff
        env:
          LINT_PATHS: ${{ inputs.lint-paths }}
        run: |
          ruff check "$LINT_PATHS"
          ruff format --check "$LINT_PATHS"

      - name: Run pytest
        env:
          TEST_PATHS: ${{ inputs.test-paths }}
        run: |
          found=0
          for path in $TEST_PATHS; do
            if [ -e "$path" ]; then
              found=1
            fi
          done
          if [ "$found" -eq 0 ]; then
            echo "No test path found, skipping."
            exit 0
          fi
          # shellcheck disable=SC2086
          pytest $TEST_PATHS
```

`$TEST_PATHS` et `$LINT_PATHS` transitent par `env:` et ne sont donc jamais du code shell. `$TEST_PATHS` reste non quoté dans la boucle et dans l'appel `pytest` : c'est une liste séparée par des espaces, et le découpage en mots est voulu.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_ci_python_wiring.bats`
Expected: PASS — 8 tests

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci-python.yml'))"`
Expected: aucune erreur.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci-python.yml tests/test_ci_python_wiring.bats
git commit -m "ci: add reusable python workflow"
```

---

### Task 2: Workflow réutilisable `ci-rust.yml`

**Files:**
- Create: `.github/workflows/ci-rust.yml`
- Test: `tests/test_ci_rust_wiring.bats`

**Interfaces:**
- Consumes: rien du socle.
- Produces: workflow réutilisable avec une entrée optionnelle `manifest-path` (string, défaut `Cargo.toml`). Job nommé `rust`, non requis par la protection.

`desk` est un espace de travail Cargo avec `Cargo.toml` à la racine et `agent/Cargo.toml` : `--manifest-path` doit être paramétrable.

- [ ] **Step 1: Write the failing test**

Créer `tests/test_ci_rust_wiring.bats` :

```bash
#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/ci-rust.yml"
}

@test "ci-rust workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "exposes an overridable manifest path" {
    grep -q "manifest-path:" "$WF"
}

@test "checks formatting, lints and tests" {
    grep -q "cargo fmt" "$WF"
    grep -q "cargo clippy" "$WF"
    grep -q "cargo test" "$WF"
}

# A warning that does not fail the build is a warning nobody fixes.
@test "treats clippy warnings as errors" {
    grep -q -- "-D warnings" "$WF"
}

@test "caches the cargo registry and build output" {
    grep -q "Swatinem/rust-cache" "$WF"
}

@test "passes github expressions through env, never into run blocks" {
    run grep -nE '^ +run:.*\$\{\{' "$WF"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_ci_rust_wiring.bats`
Expected: FAIL — le fichier n'existe pas.

- [ ] **Step 3: Write minimal implementation**

Créer `.github/workflows/ci-rust.yml` :

```yaml
name: CI Rust

on:
  workflow_call:
    inputs:
      manifest-path:
        description: Path to the Cargo manifest
        type: string
        default: Cargo.toml

jobs:
  rust:
    name: Rust checks
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install the toolchain
        run: rustup component add rustfmt clippy

      - uses: Swatinem/rust-cache@v2

      - name: Check formatting
        env:
          MANIFEST: ${{ inputs.manifest-path }}
        run: cargo fmt --manifest-path "$MANIFEST" --all --check

      - name: Run clippy
        env:
          MANIFEST: ${{ inputs.manifest-path }}
        run: cargo clippy --manifest-path "$MANIFEST" --all-targets -- -D warnings

      - name: Run tests
        env:
          MANIFEST: ${{ inputs.manifest-path }}
        run: cargo test --manifest-path "$MANIFEST" --all-targets
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_ci_rust_wiring.bats`
Expected: PASS — 7 tests

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci-rust.yml'))"`
Expected: aucune erreur.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci-rust.yml tests/test_ci_rust_wiring.bats
git commit -m "ci: add reusable rust workflow"
```

---

### Task 3: Workflow réutilisable `ci-node.yml`

**Files:**
- Create: `.github/workflows/ci-node.yml`
- Test: `tests/test_ci_node_wiring.bats`

**Interfaces:**
- Consumes: rien du socle.
- Produces: workflow réutilisable avec trois entrées optionnelles :
  - `node-version` (string, défaut `20`)
  - `working-directory` (string, défaut `.`)
  - `scripts` (string, défaut `typecheck lint test`) — scripts npm à exécuter s'ils existent

Job nommé `node`, non requis par la protection.

**Contrainte tirée du réel.** `marketplace` a son `package.json` sous `frontend/`, d'où `working-directory`. Et aucun des dépôts n'a la garantie de définir les trois scripts : chacun n'est lancé que s'il figure dans `package.json`, faute de quoi un dépôt sans script `lint` échouerait sur `npm run lint`.

- [ ] **Step 1: Write the failing test**

Créer `tests/test_ci_node_wiring.bats` :

```bash
#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/ci-node.yml"
}

@test "ci-node workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "exposes an overridable node version" {
    grep -q "node-version:" "$WF"
}

# marketplace keeps its package.json under frontend/.
@test "exposes an overridable working directory" {
    grep -q "working-directory:" "$WF"
}

@test "exposes an overridable script list" {
    grep -q "scripts:" "$WF"
}

# A repository without a lint script must not fail on npm run lint.
@test "runs a script only when package.json defines it" {
    grep -q "npm pkg get" "$WF"
}

@test "prefers a reproducible install" {
    grep -q "npm ci" "$WF"
}

@test "passes github expressions through env, never into run blocks" {
    run grep -nE '^ +run:.*\$\{\{' "$WF"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_ci_node_wiring.bats`
Expected: FAIL — le fichier n'existe pas.

- [ ] **Step 3: Write minimal implementation**

Créer `.github/workflows/ci-node.yml` :

```yaml
name: CI Node

on:
  workflow_call:
    inputs:
      node-version:
        description: Node.js version to run against
        type: string
        default: "20"
      working-directory:
        description: Directory holding package.json
        type: string
        default: "."
      scripts:
        description: Space-separated npm scripts to run when defined
        type: string
        default: typecheck lint test

jobs:
  node:
    name: Node checks
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}

      - name: Install dependencies
        env:
          WORKDIR: ${{ inputs.working-directory }}
        run: |
          cd "$WORKDIR"
          if [ -f package-lock.json ]; then
            npm ci
          else
            npm install
          fi

      - name: Run the defined scripts
        env:
          WORKDIR: ${{ inputs.working-directory }}
          SCRIPTS: ${{ inputs.scripts }}
        run: |
          cd "$WORKDIR"
          for script in $SCRIPTS; do
            if [ "$(npm pkg get "scripts.$script")" = "{}" ]; then
              echo "No $script script, skipping."
              continue
            fi
            echo "Running $script"
            npm run "$script"
          done
```

`npm pkg get scripts.<name>` rend `{}` quand le script n'existe pas : c'est ce
qui permet de sauter proprement plutôt que d'échouer.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_ci_node_wiring.bats`
Expected: PASS — 8 tests

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci-node.yml'))"`
Expected: aucune erreur.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci-node.yml tests/test_ci_node_wiring.bats
git commit -m "ci: add reusable node workflow"
```

---

### Task 4: Adoption par `installer`

Premier dépôt consommateur après le pilote, et le plus exigeant : 40 fichiers Python, 28 shell, aucun manifeste Python.

**Files:**
- Create (dans `nivuus/installer`) : `.github/workflows/ci.yml`, `.github/dependabot.yml`, `.gitleaks.toml`

**Interfaces:**
- Consumes: `policy.yml`, `security.yml`, `ci-shell.yml` (plan 1), `ci-python.yml` (Task 1).
- Produces: rien pour les tâches suivantes.

- [ ] **Step 1: Measure before changing anything**

Depuis un clone à jour d'`installer`, mesurer ce que le socle refuserait :

```bash
S=/home/mallanic/Projects/Nivuus/org-profile/scripts
find . -path "*/.git" -prune -o -type f \( -name '*.py' -o -name '*.sh' \) -print | sed 's|^\./||' > /tmp/inst-files.txt
"$S/check-file-size.sh" < /tmp/inst-files.txt
"$S/check-english.sh" < /tmp/inst-files.txt | grep -c ':' || true
```

Ces chiffres n'ont pas à être nuls : le contrôle « anglais » ne juge que les lignes ajoutées par une pull request, et le contrôle de taille ne s'applique qu'aux fichiers touchés. Ils servent à savoir ce qui attend la première modification réelle, et à le consigner.

- [ ] **Step 2: Check that ruff passes, or record what it costs**

```bash
pipx run ruff check .
pipx run ruff format --check .
```

Si ruff signale des erreurs, ne pas les corriger dans cette tâche. Choisir entre deux options et la consigner dans le rapport :
- ajouter un `pyproject.toml` minimal désactivant les règles concernées, si elles sont nombreuses et stylistiques ;
- corriger, si elles sont peu nombreuses.

Un dépôt qui adopte le socle avec une CI rouge contredit le principe du spec.

- [ ] **Step 3: Add the gitleaks allowlist**

L'audit du 27 août a relevé une unique détection : `docs/homeassistant-cli.md`, la ligne `curl -H "Authorization: Bearer YOUR_TOKEN"`, un placeholder de documentation. Sans allowlist, toute pull request retouchant ce fichier serait bloquée.

Créer `.gitleaks.toml` :

```toml
[extend]
useDefault = true

[[rules]]
id = "curl-auth-header"
  [rules.allowlist]
  description = "Documentation placeholder, not a credential"
  regexes = ['''YOUR_TOKEN''']
```

- [ ] **Step 4: Create the caller workflow**

`.github/workflows/ci.yml` :

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
  python:
    uses: nivuus/.github/.github/workflows/ci-python.yml@main
    with:
      test-paths: tests scripts/tests
  shell:
    uses: nivuus/.github/.github/workflows/ci-shell.yml@main
    with:
      test-dirs: ""
      shellcheck-paths: "."
```

`test-dirs` est vide : `installer` n'a pas de suite bats, et `ci-shell.yml` saute proprement un répertoire absent. Le job reste utile pour shellcheck.

- [ ] **Step 5: Create the dependabot configuration**

`.github/dependabot.yml` :

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

Pas d'écosystème `pip` : le dépôt n'a aucun manifeste Python à surveiller.

- [ ] **Step 6: Open the pull request**

```bash
git checkout -b ci/adopt-socle
git add .github/workflows/ci.yml .github/dependabot.yml .gitleaks.toml
git commit -m "ci: adopt the shared nivuus socle"
git push -u origin HEAD
gh pr create --repo nivuus/installer --fill
```

- [ ] **Step 7: Watch the checks and report**

Run: `gh pr checks --repo nivuus/installer --watch`
Expected: `policy / Coding rules`, `security / Secrets and dependencies`, `python`, `shell` au vert.

Si un check échoue, consigner la cause dans le rapport avant toute correction : c'est la première fois que `ci-python.yml` tourne sur du vrai code, et un échec en dit plus sur le workflow que sur le dépôt.

---

### Task 5: Adoption par `mqtt` et `marketplace`

Deux dépôts publics, tous deux Node, tous deux quasi vides. Regroupés parce que le changement est le même et que leur revue tient en un seul diff.

**Files:**
- Create (dans `nivuus/mqtt`) : `.github/workflows/ci.yml`, `.github/dependabot.yml`
- Create (dans `nivuus/marketplace`) : `.github/workflows/ci.yml`, `.github/dependabot.yml`

**Interfaces:**
- Consumes: `policy.yml`, `security.yml`, `ci-node.yml` (Task 3), `ci-python.yml` (Task 1), `ci-shell.yml`.
- Produces: rien.

- [ ] **Step 1: mqtt — caller workflow**

`mqtt` a 74 fichiers TypeScript, 8 shell, un `package.json` à la racine.

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
  node:
    uses: nivuus/.github/.github/workflows/ci-node.yml@main
  shell:
    uses: nivuus/.github/.github/workflows/ci-shell.yml@main
    with:
      test-dirs: ""
      shellcheck-paths: "."
```

- [ ] **Step 2: marketplace — caller workflow**

`marketplace` a 12 fichiers Python, 7 TypeScript, et son `package.json` sous `frontend/`.

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
  node:
    uses: nivuus/.github/.github/workflows/ci-node.yml@main
    with:
      working-directory: frontend
  python:
    uses: nivuus/.github/.github/workflows/ci-python.yml@main
    with:
      test-paths: tests
```

`marketplace` n'a pas de répertoire `tests` : le workflow Python doit le sauter proprement, ce que la Task 1 garantit. C'est la vérification en conditions réelles de ce comportement.

- [ ] **Step 3: dependabot for both**

Dans `mqtt`, `.github/dependabot.yml` :

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

Dans `marketplace`, identique mais avec `directory: "/frontend"` pour l'entrée npm.

- [ ] **Step 4: Open both pull requests**

```bash
# dans chaque dépôt
git checkout -b ci/adopt-socle
git add .github/workflows/ci.yml .github/dependabot.yml
git commit -m "ci: adopt the shared nivuus socle"
git push -u origin HEAD
gh pr create --fill
```

- [ ] **Step 5: Watch the checks**

Run: `gh pr checks --repo nivuus/mqtt --watch` puis `gh pr checks --repo nivuus/marketplace --watch`
Expected: tous les checks au vert.

Consigner en particulier ce que fait `ci-python.yml` sur `marketplace`, qui n'a ni manifeste ni tests : c'est le cas limite que la Task 1 prétend gérer.

---

### Task 6: Protection des trois dépôts publics restants

**Files:**
- Aucun fichier. Configuration serveur appliquée par `scripts/apply-org-config.sh`.

**Interfaces:**
- Consumes: `scripts/apply-org-config.sh` (plan 1), les pull requests des Tasks 4 et 5, mergées.
- Produces: rien.

`shell` et `.github` sont déjà protégés ; restent `installer`, `mqtt` et
`marketplace`.

L'ordre compte, et il a déjà mordu une fois : activer la protection avant de merger bloquerait la pull request qui apporte la CI que la protection exige.

- [ ] **Step 1: Merge the three pull requests**

```bash
gh pr merge --repo nivuus/installer --squash --delete-branch
gh pr merge --repo nivuus/mqtt --squash --delete-branch
gh pr merge --repo nivuus/marketplace --squash --delete-branch
```

- [ ] **Step 2: Confirm the check names GitHub actually reports**

Pour chacun des trois dépôts, sur le commit de merge :

```bash
for r in installer mqtt marketplace; do
  echo "== $r =="
  sha=$(gh api "repos/nivuus/$r/commits/main" --jq .sha)
  gh api "repos/nivuus/$r/commits/$sha/check-runs" --jq '.check_runs[].name'
done
```

Les deux contextes `policy / Coding rules` et `security / Secrets and dependencies` doivent apparaître à l'identique. Une divergence bloquerait tous les merges du dépôt : la corriger dans `apply-org-config.sh` avant l'étape suivante.

- [ ] **Step 3: Apply, dry-run first**

```bash
./scripts/apply-org-config.sh --dry-run nivuus/installer nivuus/mqtt nivuus/marketplace
./scripts/apply-org-config.sh nivuus/installer nivuus/mqtt nivuus/marketplace
```

- [ ] **Step 4: Verify each protection**

```bash
for r in installer mqtt marketplace; do
  echo "== $r =="
  gh api "repos/nivuus/$r/branches/main/protection" \
    --jq '{checks: .required_status_checks.contexts, admins: .enforce_admins.enabled,
           reviews: .required_pull_request_reviews.required_approving_review_count,
           linear: .required_linear_history.enabled, force: .allow_force_pushes.enabled}'
done
```

Expected pour chacun : les deux contextes, `admins: true`, `reviews: 0`, `linear: true`, `force: false`.

- [ ] **Step 5: Prove a direct push is refused**

Sur l'un des trois, au choix :

```bash
git commit --allow-empty -m "chore: verify protection"
git push origin main
git reset --hard origin/main
```

Expected: rejet `GH006 ... Changes must be made through a pull request`. Si le push réussit, la protection n'est pas active : reprendre à l'étape 3.

---

### Task 7: Adoption par les trois dépôts privés

`desk`, `home-stock` et `design`. Le plan Free interdit la protection de branche et le secret scanning natif sur un dépôt privé : ils reçoivent la CI, les fichiers de santé et Dependabot, mais aucune règle serveur. C'est l'asymétrie assumée au § 3 du spec.

**Files:**
- Modify (dans `nivuus/home-stock`) : branche par défaut `master` → `main`
- Create (dans chacun des trois) : `.github/workflows/ci.yml`, `.github/dependabot.yml`, `CONTRIBUTING.md`, `SECURITY.md`, `PULL_REQUEST_TEMPLATE.md`

**Interfaces:**
- Consumes: tous les workflows du socle ; les fichiers de santé de `nivuus/.github` comme source à copier.
- Produces: rien.

**Pourquoi copier les fichiers de santé.** GitHub ne propage les fichiers de santé par défaut qu'aux dépôts **publics** de l'organisation. Les trois privés doivent donc en embarquer une copie, sans quoi un contributeur n'aurait aucun texte décrivant les règles que la CI lui applique.

- [ ] **Step 1: Rename home-stock's default branch**

```bash
gh api -X POST repos/nivuus/home-stock/branches/master/rename -f new_name=main
cd /path/to/home-stock
git branch -m master main
git fetch origin
git branch -u origin/main main
git remote set-head origin -a
```

Run: `gh api repos/nivuus/home-stock --jq .default_branch`
Expected: `main`

Puis chercher les références en dur : `grep -rn "master" --include='*.yml' --include='*.md' --include='*.py' .` et corriger celles qui désignent la branche.

- [ ] **Step 2: Copy the health files into each private repository**

Depuis un clone de `nivuus/.github`, dans chacun des trois dépôts :

```bash
cp /path/to/.github/CONTRIBUTING.md .
cp /path/to/.github/SECURITY.md .
cp /path/to/.github/PULL_REQUEST_TEMPLATE.md .github/
```

Ces fichiers sont en français, et le restent.

Une nuance à porter dans le `SECURITY.md` copié : il renvoie au signalement privé de GitHub, indisponible sur un dépôt privé en plan Free. Y ajouter une phrase le disant, plutôt que de laisser une instruction inapplicable :

```markdown
> Ce dépôt est privé : le signalement passe directement par les mainteneurs,
> l'onglet Security de GitHub n'y proposant pas le signalement privé.
```

- [ ] **Step 3: desk — caller workflow**

159 fichiers Rust, 82 TypeScript, 16 shell. `Cargo.toml` et `package.json` à la racine.

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
  rust:
    uses: nivuus/.github/.github/workflows/ci-rust.yml@main
  node:
    uses: nivuus/.github/.github/workflows/ci-node.yml@main
  shell:
    uses: nivuus/.github/.github/workflows/ci-shell.yml@main
    with:
      test-dirs: ""
      shellcheck-paths: "."
```

- [ ] **Step 4: home-stock — caller workflow**

36 fichiers Python, `pytest.ini`, un répertoire `tests`.

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
  python:
    uses: nivuus/.github/.github/workflows/ci-python.yml@main
    with:
      test-paths: tests
```

- [ ] **Step 5: design — caller workflow**

Aucun code : seul le socle s'applique.

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

C'est le cas qui vérifie une promesse du socle : il doit s'appliquer tel quel à un dépôt sans code.

- [ ] **Step 6: dependabot for each**

Les trois reçoivent l'entrée `github-actions`. `desk` y ajoute `cargo` et `npm`, `home-stock` rien de plus (aucun manifeste pip). Modèle :

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

- [ ] **Step 7: Enable what the Free plan does allow**

Les alertes de vulnérabilité et les correctifs automatiques sont gratuits, y compris en privé. `apply-org-config.sh` les active et saute proprement le reste :

```bash
./scripts/apply-org-config.sh nivuus/desk nivuus/home-stock nivuus/design
```

Expected: pour chacun, un avertissement indiquant que le dépôt est privé et que la protection est sautée, et un code de sortie 0.

- [ ] **Step 8: Open the three pull requests and watch**

```bash
# dans chaque dépôt
git checkout -b ci/adopt-socle
git add .github CONTRIBUTING.md SECURITY.md
git commit -m "ci: adopt the shared nivuus socle"
git push -u origin HEAD
gh pr create --fill
```

Run: `gh pr checks --repo nivuus/desk --watch`, puis la même commande pour
`nivuus/home-stock` et `nivuus/design`.

`desk` est le cas le plus lourd : 159 fichiers Rust jamais passés par clippy en CI. Un échec y est probable et instructif ; le consigner avant de corriger.

---

### Task 8: CodeQL sur les deux dépôts publics qui portent du code

Le § 6.4 du spec prévoit CodeQL sur `installer` et `shell`, l'analyse n'étant
gratuite que sur les dépôts publics. Ni le plan 1 ni les tâches précédentes ne
l'ont mis en place : c'est une lacune de couverture relevée à la relecture.

`mqtt` et `marketplace` en relèvent aussi sur le principe, mais ils sont
quasi vides ; ils seront ajoutés quand ils porteront du code.

**Files:**
- Create (dans `nivuus/.github`) : `.github/workflows/codeql.yml`
- Test (dans `nivuus/.github`) : `tests/test_codeql_wiring.bats`
- Create (dans `nivuus/installer` et `nivuus/shell`) : l'appel dans `ci.yml`

**Interfaces:**
- Consumes: rien du socle.
- Produces: workflow réutilisable avec une entrée obligatoire `languages`
  (string) — liste de langages CodeQL séparés par des virgules.

CodeQL ne connaît ni Bash ni Zsh : sur `shell`, l'analyse ne porterait sur
rien. La tâche l'active donc sur `installer` (Python) seulement, et consigne
que `shell` n'est pas couvrable par cet outil — ce que le spec ne pouvait pas
savoir au moment de sa rédaction.

- [ ] **Step 1: Write the failing test**

Créer `tests/test_codeql_wiring.bats` dans `nivuus/.github` :

```bash
#!/usr/bin/env bats

setup() {
    WF="${BATS_TEST_DIRNAME}/../.github/workflows/codeql.yml"
}

@test "codeql workflow exists" {
    [ -f "$WF" ]
}

@test "is callable by other repositories" {
    grep -q "workflow_call:" "$WF"
}

@test "takes the languages to analyse as an input" {
    grep -q "languages:" "$WF"
}

@test "runs the three codeql steps" {
    grep -q "github/codeql-action/init" "$WF"
    grep -q "github/codeql-action/autobuild" "$WF"
    grep -q "github/codeql-action/analyze" "$WF"
}

# Uploading results needs this permission; without it the run fails at the end,
# after doing all the work.
@test "grants the security-events permission" {
    grep -q "security-events: write" "$WF"
}

@test "passes github expressions through env, never into run blocks" {
    run grep -nE '^ +run:.*\$\{\{' "$WF"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_codeql_wiring.bats`
Expected: FAIL — le fichier n'existe pas.

- [ ] **Step 3: Write minimal implementation**

Créer `.github/workflows/codeql.yml` :

```yaml
name: CodeQL

on:
  workflow_call:
    inputs:
      languages:
        description: Comma-separated CodeQL languages to analyse
        type: string
        required: true

jobs:
  codeql:
    name: CodeQL analysis
    runs-on: ubuntu-latest
    permissions:
      security-events: write
      actions: read
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Initialise CodeQL
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ inputs.languages }}

      - name: Autobuild
        uses: github/codeql-action/autobuild@v3

      - name: Analyse
        uses: github/codeql-action/analyze@v3
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_codeql_wiring.bats`
Expected: PASS — 6 tests

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/codeql.yml'))"`
Expected: aucune erreur.

- [ ] **Step 5: Commit the socle change through a pull request**

```bash
git add .github/workflows/codeql.yml tests/test_codeql_wiring.bats
git commit -m "ci: add reusable codeql workflow"
git push -u origin HEAD
gh pr create --repo nivuus/.github --fill
```

Le dépôt est protégé : attendre les checks, puis merger en squash.

- [ ] **Step 6: Call it from installer**

Dans `.github/workflows/ci.yml` de `nivuus/installer`, ajouter :

```yaml
  codeql:
    uses: nivuus/.github/.github/workflows/codeql.yml@main
    with:
      languages: python
```

- [ ] **Step 7: Record why shell is not covered**

CodeQL ne prend en charge ni Bash ni Zsh. `nivuus/shell` ne peut donc pas être
analysé par cet outil, malgré ce qu'annonce le § 6.4 du spec. Ce qui en tient
lieu pour ce dépôt : `shellcheck -S warning` sur tout l'arbre et `zsh -n` sur
les sources zsh, tous deux déjà actifs.

Consigner ce constat dans le document de résultats de la Task 9, et ne pas
laisser le spec affirmer une couverture qui n'existe pas.

---

### Task 9: Clore l'uniformisation

**Files:**
- Create: `docs/superpowers/plans/2026-08-27-extension-socle-nivuus-resultats.md`
- Modify: `README.md` du dépôt `.github`

**Interfaces:**
- Consumes: l'ensemble des tâches précédentes.
- Produces: la trace écrite de l'état final.

- [ ] **Step 1: Verify the whole organisation in one pass**

```bash
for r in .github shell installer mqtt marketplace desk home-stock design; do
  vis=$(gh api "repos/nivuus/$r" --jq .visibility)
  br=$(gh api "repos/nivuus/$r" --jq .default_branch)
  ci=$(gh api "repos/nivuus/$r/contents/.github/workflows/ci.yml" --jq .name 2>/dev/null || echo "ABSENT")
  prot=$(gh api "repos/nivuus/$r/branches/main/protection" --jq '.required_status_checks.contexts | length' 2>/dev/null || echo "-")
  printf '%-14s %-8s %-6s ci=%-10s checks=%s\n' "$r" "$vis" "$br" "$ci" "$prot"
done
```

Expected: les huit sur `main`, les huit avec un `ci.yml`, les cinq publics avec 2 checks requis, les trois privés avec `-`.

- [ ] **Step 2: Write the results document**

Consigner : ce qui a été appliqué à chaque dépôt, les échecs rencontrés et leur cause, les dettes ouvertes et où elles sont suivies, et les décisions prises en cours de route.

- [ ] **Step 3: Document the socle in its README**

Le `README.md` de `nivuus/.github` décrit aujourd'hui le profil de l'organisation. Y ajouter une section, en français, expliquant comment un nouveau dépôt adopte le socle : le fichier `ci.yml` à créer, les workflows disponibles avec leurs entrées, et la commande `apply-org-config.sh` à lancer.

Sans cela, la connaissance de ce socle vit dans un plan que personne ne relira.

- [ ] **Step 4: Commit through a pull request**

Le dépôt est protégé : passer par une branche et une pull request, comme n'importe quel changement.

---

## Hors périmètre

- Les douze dépôts archivés, en lecture seule.
- Le nettoyage de l'historique de `desk`, où l'audit du 27 août a relevé 46 détections dans des journaux de sessions d'authentification. C'est une décision du propriétaire, documentée dans `gitleaks-audit-2026-08-27.md`.
- Les quatre dettes de `nivuus/shell`, suivies dans ses issues #5 à #8.
- L'extraction des chaînes d'interface vers un système d'internationalisation.
