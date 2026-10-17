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
| `dependabot-auto-merge.yml` | auto-merge des mises à jour Dependabot sans risque | `allowed-update-types` |

## CodeQL exige une permission de l'appelant

`codeql.yml` exige que le dépôt appelant lui accorde des permissions — comme
`dependabot-auto-merge.yml`, voir plus bas : il lui faut
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

## Auto-merge des pull requests Dependabot

`dependabot-auto-merge.yml` active l'auto-merge de GitHub sur les pull requests
ouvertes par Dependabot : elles se fusionnent seules, en squash, dès que les
checks exigés par la protection de branche passent. Le workflow ne fusionne
jamais directement ; ce sont toujours les checks qui décident.

Passent sans revue les mises à jour patch et mineures, jamais une majeure. Pour
une dépendance encore en 0.x, seuls les patchs passent : sous 1.0, une mineure
a le droit de casser l'API (str0m 0.21 → 0.24). Une pull request groupée est
jugée dépendance par dépendance et la plus stricte décide : une seule majeure
dans le groupe, et tout attend une revue humaine. L'entrée
`allowed-update-types` (`semver-patch`, `semver-minor`, `semver-major`) resserre
ou élargit la liste, sans jamais lever la règle des 0.x.

Comme pour CodeQL, le job appelant doit accorder les permissions, faute de quoi
l'exécution entière finit en `startup_failure` :

```yaml
  dependabot-auto-merge:
    uses: nivuus/.github/.github/workflows/dependabot-auto-merge.yml@main
    permissions:
      contents: write
      pull-requests: write
```

Le job se saute de lui-même sur tout autre auteur que `dependabot[bot]`, et sur
un push.

Une branche Dependabot réécrite par quelqu'un d'autre (un `gh pr update-branch
--rebase`, qui recrée les commits sans signature, ou un commit de correction
poussé dessus) n'est jamais fusionnée seule : le job passe au vert et la laisse
à une revue humaine, en le disant dans son journal. Pour garder l'auto-merge,
commenter `@dependabot rebase` plutôt que de mettre la branche à jour soi-même.

Le réglage **Allow auto-merge** du dépôt (Settings → General → Pull Requests)
doit être activé. Sinon `gh pr merge --auto` échoue et le job passe au rouge :
c'est voulu, plutôt qu'une pull request qui attend sans dire pourquoi.

Une fusion faite par l'auto-merge activé avec le `GITHUB_TOKEN` ne déclenche
aucun workflow `push` : ni la CI sur `main`, ni `release.yml`. Sans effet sur
les versions, puisque Dependabot préfixe ses commits `ci` ou `chore`, que
`derive-version.sh` ne publie jamais : la mise à jour part avec la prochaine
release `feat` ou `fix`.

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
