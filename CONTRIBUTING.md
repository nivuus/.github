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
