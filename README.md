# .github

Organisation-level files for [Nivuus](https://github.com/nivuus).

- `profile/README.md` — the profile shown at the top of github.com/nivuus
- `profile/assets/` — wordmark, exported from the brand assets

Brand rules live in the private `design` repository. The name is always written
`Nivuus`, never `NIVUUS` or `nivuus`, and the mark is never recomposed.

## Le socle partagé

Ce dépôt héberge les workflows réutilisables et les règles communes aux dépôts
de l'organisation. Un dépôt les adopte avec un seul fichier.

### Adopter le socle

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

Les identifiants `policy` et `security` sont imposés : GitHub nomme les checks
`policy / Coding rules` et `security / Secrets and dependencies`, et c'est sous
ces noms exacts que la protection de branche les exige. Les renommer bloque
tous les merges du dépôt.

Puis, pour un dépôt public :

```bash
scripts/apply-org-config.sh nivuus/<dépôt>
```

Le script applique la protection, la stratégie de merge et les réglages de
sécurité. Sur un dépôt privé il saute proprement ce que le plan Free interdit.

### Workflows de langage

Chacun s'ajoute au besoin, avec des entrées toutes optionnelles.

| Workflow | Ce qu'il fait | Entrées |
|---|---|---|
| `ci-shell.yml` | shellcheck, bats, `zsh -n` | `test-dirs`, `shellcheck-paths`, `zsh-syntax-paths` |
| `ci-python.yml` | ruff, pytest | `python-version`, `test-paths`, `lint-paths`, `changed-only` |
| `ci-rust.yml` | fmt, clippy, test | `manifest-path` |
| `ci-node.yml` | scripts npm définis | `node-version`, `working-directory`, `scripts` |
| `codeql.yml` | analyse sémantique | `languages` (**obligatoire**) |

## CodeQL exige une permission de l'appelant

Parmi les workflows réutilisables de ce dépôt, `codeql.yml` est le seul qui
exige que le dépôt appelant lui accorde des permissions : il lui faut
`security-events: write` pour publier ses résultats, `actions: read` et
`contents: read`, et un workflow appelé ne peut jamais détenir plus de droits
que celui qui l'appelle. Sans ce bloc, GitHub ne se contente pas de faire
échouer le job CodeQL : il refuse de démarrer l'exécution entière, avec un
`startup_failure` sans aucun log — déroutant, puisque rien ne pointe vers la
cause.

Le job appelant doit donc porter le bloc `permissions` lui-même :

```yaml
  codeql:
    uses: nivuus/.github/.github/workflows/codeql.yml@main
    permissions:
      security-events: write
      actions: read
      contents: read
    with:
      languages: python
```

Chaque workflow saute proprement ce qui n'existe pas : un dépôt sans manifeste,
sans tests ou sans le script npm attendu ne sera pas mis en échec pour autant.

`security.yml` accepte aussi `python-version`, pour un dépôt dont le manifeste
exige un interpréteur particulier.

### Les trois règles

**Anglais dans le code.** Identifiants, commentaires, docstrings, messages de
commit et noms de branches. Les chaînes affichées à l'utilisateur, les README,
CHANGELOG et `docs/` restent en français. Seules les **lignes ajoutées** par
une pull request sont jugées.

**500 lignes par fichier source.** Fichiers de test et fichiers générés
exemptés. La règle porte sur le fichier entier.

**Conventional Commits.** Les commits de la pull request et son titre, celui-ci
devenant le message de squash.

### Échappements

| Marqueur | Portée | Usage |
|---|---|---|
| `policy: allow-fr` | une ligne | dans un commentaire ; sans effet dans une chaîne |
| `policy: allow-fr-file` | le fichier | texte utilisateur multiligne, un heredoc par exemple |
| `policy: allow-long-file` | le fichier | dette de longueur assumée, avec sa raison |

Tous exigent d'éditer le fichier : ils apparaissent donc en revue, ce qui est
le but.

### Modifier le socle

`main` est protégé, et le dépôt s'applique ses propres règles. Toute
modification passe par une pull request, avec `bats tests/` au vert.
