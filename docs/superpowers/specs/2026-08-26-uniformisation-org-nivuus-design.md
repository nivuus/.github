# Uniformisation de l'organisation GitHub Nivuus

> Design validé le 26 août 2026. Couvre la sécurité, la branche principale,
> les workflows CI/CD et les règles de codage des dépôts de l'organisation
> `nivuus`.

## 1. Objectif

Les huit dépôts actifs de l'organisation ont des conventions divergentes :
deux branches principales différentes, trois dépôts sans aucune CI, aucune
protection de branche, secret scanning désactivé partout. Ce document définit
un socle commun et le chemin pour l'appliquer.

## 2. État des lieux

| Dépôt | Visibilité | Branche | Stack | CI existante |
|---|---|---|---|---|
| shell | public | master | Bash/Zsh | release.yml, tests.yml |
| installer | public | main | Python, TypeScript | build-iso.yml |
| desk | privé | main | Rust, TypeScript | aucune |
| home-stock | privé | master | Python | aucune |
| design | privé | main | HTML | aucune |
| .github | public | main | — | aucune |
| mqtt | public | main | — | aucune |
| marketplace | public | main | — | aucune |

Douze dépôts supplémentaires sont archivés et restent hors périmètre.

Mesures relevées le 26 août 2026 :

- 14 fichiers source dépassent 500 lignes, sur environ 520 fichiers
  (installer 10, desk 2, shell 1, home-stock 1).
- 298 fichiers contiennent du français (desk 256, installer 26, home-stock 9,
  shell 7). Aucun dépôt n'a de système d'internationalisation : les chaînes
  affichées à l'utilisateur sont écrites en dur dans le code.
- `delete_branch_on_merge` est désactivé partout.

## 3. Contrainte structurante : le plan Free

L'organisation est en plan Free avec un siège. GitHub y refuse deux choses :

- la protection de branche sur les dépôts **privés** (`403 Upgrade to GitHub Pro`) ;
- les **rulesets d'organisation** (`403 Upgrade to GitHub Team`).

**Décision.** Rester en Free. Les règles serveur s'appliquent aux cinq dépôts
publics ; sur `desk`, `home-stock` et `design`, le filet est purement
applicatif — CI et hooks locaux.

Conséquence assumée : sur les dépôts privés, rien n'empêche techniquement un
push direct sur `main`. La CI y détecte les problèmes après coup au lieu de
les bloquer avant. Un passage ultérieur en Team supprimerait cette asymétrie
sans remettre en cause le reste du design.

## 4. Architecture : socle centralisé

Le dépôt public `nivuus/.github` héberge des workflows réutilisables
(`workflow_call`) et les fichiers de santé communs. Chaque dépôt n'embarque
qu'un appelant d'une dizaine de lignes.

```
.github/
├── .github/workflows/
│   ├── policy.yml          # réutilisable : règles de codage
│   ├── security.yml        # réutilisable : secrets et dépendances
│   ├── ci-node.yml
│   ├── ci-python.yml
│   ├── ci-rust.yml
│   └── ci-shell.yml
├── scripts/apply-org-config.sh
├── CONTRIBUTING.md
├── SECURITY.md
├── PULL_REQUEST_TEMPLATE.md
└── dependabot.yml
```

Appelant type, présent dans chaque dépôt :

```yaml
# .github/workflows/ci.yml
name: CI
on:
  pull_request:
  push: { branches: [main] }
jobs:
  policy:   { uses: nivuus/.github/.github/workflows/policy.yml@main }
  security: { uses: nivuus/.github/.github/workflows/security.yml@main }
  test:     { uses: nivuus/.github/.github/workflows/ci-python.yml@main }
```

Un workflow réutilisable hébergé dans un dépôt public est appelable depuis un
dépôt privé de la même organisation : `desk`, `home-stock` et `design`
bénéficient donc du socle malgré leur visibilité.

**Limite connue.** Les fichiers de santé par défaut (`CONTRIBUTING.md`,
`SECURITY.md`, templates) ne se propagent qu'aux dépôts publics. Les trois
dépôts privés en embarquent une copie, synchronisée par
`apply-org-config.sh`.

**Alternatives écartées.** La copie autonome dans chaque dépôt supprime la
dépendance croisée mais garantit la divergence à moyen terme. Un outil de
synchronisation dédié serait disproportionné pour huit dépôts.

## 5. Règles de codage — `policy.yml`

Principe directeur : **le workflow n'inspecte que les fichiers ajoutés ou
modifiés dans la pull request**, déterminés par
`git diff --name-only origin/main...HEAD`. Aucune vérification rétroactive,
donc aucune CI rouge au démarrage ; la dette se résorbe à mesure qu'on touche
aux fichiers.

### 5.1 Limite de 500 lignes

S'applique aux fichiers `.sh`, `.zsh`, `.py`, `.ts`, `.tsx`, `.js`, `.rs`.

Exclusions :

- fichiers générés : `Cargo.lock`, `package-lock.json`, `*.pb.rs`, tout
  fichier sous un répertoire `generated/` ;
- documentation et fichiers de configuration ;
- **fichiers de test**, exemptés délibérément. Un fichier de test long reste
  lisible parce qu'il aligne des cas indépendants ; la règle vise le couplage
  du code de production, pas le volume de couverture.

Échec bloquant. Le message indique le chemin, le nombre de lignes et invite
au découpage.

### 5.2 Anglais dans le code

| Élément | Langue |
|---|---|
| Identifiants (variables, fonctions, types) | Anglais |
| Commentaires et docstrings | Anglais |
| Messages de commit, noms de branches | Anglais |
| Chaînes affichées à l'utilisateur | Français |
| README, CHANGELOG, `docs/` | Français |

La difficulté est de distinguer un commentaire français, à refuser, d'une
chaîne d'interface française, à conserver. Le contrôle procède en deux temps :
il retire d'abord les littéraux de chaîne de chaque ligne, puis cherche dans
ce qui reste des caractères accentués ainsi qu'une liste de mots français
fréquents écrits sans accent (`fonction`, `utilisateur`, `fichier`,
`verifier`, `ajouter`, `supprimer`, et une soixantaine d'autres). Sans cette
seconde passe, `def verifier_stock()` passerait au travers.

L'heuristique produira des faux positifs. Échappement explicite :
`# policy: allow-fr` en fin de ligne, pour un nom propre, un terme métier
français sans équivalent ou un identifiant de protocole.

### 5.3 Messages de commit

Format Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`,
`test:`, `ci:`), sujet en anglais. Vérifié sur les commits de la pull request
uniquement. **Bloquant** : le format conditionne la génération du CHANGELOG et
le versionnement sémantique, donc s'il n'est pas garanti il n'est pas
exploitable.

## 6. Sécurité et branche principale

### 6.1 Renommage

`shell` et `home-stock` passent de `master` à `main`. GitHub redirige
automatiquement les anciennes références. Seuls deux fichiers référencent la
branche en dur, tous deux dans `shell` : `.github/workflows/tests.yml` et
`.github/workflows/release.yml`.

### 6.2 Configuration serveur (cinq dépôts publics)

Appliquée par `scripts/apply-org-config.sh`, idempotent et rejouable, sur
`shell`, `installer`, `.github`, `mqtt` et `marketplace` :

- pull request obligatoire, **0 approbation requise** — l'organisation n'a
  qu'un siège et GitHub interdit d'approuver sa propre PR ; exiger une revue
  bloquerait tout. Le compteur passera à 1 à l'arrivée d'un second
  développeur ;
- checks `policy` et `security` requis, avec branche à jour (`strict: true`) ;
- `enforce_admins: true` — le propriétaire est soumis aux règles. Puisque
  aucune approbation n'est exigée, la contrainte ne coûte rien au quotidien
  tout en protégeant du push accidentel ;
- force-push et suppression de branche interdits, historique linéaire ;
- squash-merge seul autorisé, `delete_branch_on_merge: true` ;
- secret scanning et push protection activés.

### 6.3 Versionnement de `shell`

`shell/.github/workflows/release.yml:240` commite un bump de version puis
exécute `git push origin HEAD:master` avec le `GITHUB_TOKEN`. Ce push serait
rejeté par la protection de branche et ferait échouer chaque release.

**Décision.** Supprimer le commit de bump. La version est dérivée du tag git
au moment du build et injectée dans les artefacts ; le CHANGELOG se génère
depuis les commits conventionnels. Plus aucun push direct à autoriser, la
protection reste absolue.

### 6.4 Sécurité applicative — `security.yml`

Appliqué aux huit dépôts :

- **gitleaks** sur le diff. Le secret scanning natif n'existant pas sur les
  dépôts privés en Free, gitleaks assure une détection identique partout,
  indépendante de la visibilité ;
- audit de dépendances selon la stack : `pip-audit`, `cargo audit`,
  `npm audit` ;
- **Dependabot** activé sur les huit dépôts — alertes et mises à jour sont
  gratuites, y compris en privé ;
- **CodeQL** sur `installer` et `shell` seulement, l'analyse n'étant gratuite
  que sur les dépôts publics.

## 7. CI par langage

| Workflow | Contenu | Dépôts |
|---|---|---|
| `ci-shell.yml` | shellcheck, suite de tests existante | shell, installer |
| `ci-python.yml` | ruff (lint et format), pytest | home-stock, installer |
| `ci-rust.yml` | `cargo fmt --check`, `clippy -D warnings`, `cargo test` | desk |
| `ci-node.yml` | `tsc --noEmit`, eslint, prettier, tests | desk, installer |

## 8. Déploiement

1. **Construire le socle** dans `nivuus/.github`, seul dépôt dont la CI ne
   dépend de rien.
2. **Pilote sur `shell`** : renommage en `main`, versionnement par tag,
   branchement sur le socle, activation de la protection. Dépôt public, petit,
   déjà outillé : les erreurs de conception du socle s'y révèlent à moindre
   coût.
3. **Point de contrôle.** Sur une pull request réelle, vérifier le
   comportement de `policy` et `security`, en particulier le taux de faux
   positifs du contrôle « anglais » sur du code existant. Si le bruit est trop
   élevé, ajuster l'heuristique ici plutôt que sur huit dépôts.
4. **Étendre** aux quatre autres dépôts publics, puis aux trois privés (CI et
   hooks seulement).
5. **Archiver** la configuration dans `apply-org-config.sh`, rejouable pour
   tout nouveau dépôt.

## 9. Hors périmètre

- Les douze dépôts archivés. Ils sont en lecture seule et les traiter
  demanderait de les désarchiver sans bénéfice.
- L'extraction des chaînes d'interface vers un système d'internationalisation.
  Le chantier concerne 298 fichiers et relève d'un projet distinct.
- Le découpage rétroactif des 14 fichiers dépassant 500 lignes, traité au fil
  des modifications conformément au principe du § 5.
