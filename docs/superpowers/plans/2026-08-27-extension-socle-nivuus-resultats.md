# Uniformisation de l'organisation Nivuus — résultats

> Clôture du 27 août 2026. Fait suite au spec du 26 août et à ses deux plans
> d'implémentation.

## Ce qui est en place

Les huit dépôts actifs de l'organisation partagent le même socle, hébergé dans
`nivuus/.github` et consommé par un fichier `ci.yml` d'une dizaine de lignes.

| Dépôt | Visibilité | Branche | Jobs | Protection |
|---|---|---|---|---|
| .github | public | main | policy, security | 2 checks requis |
| shell | public | main | policy, security, shell | 2 checks requis |
| installer | public | main | policy, security, python, shell, codeql | 2 checks requis |
| mqtt | public | main | policy, security, node, shell | 2 checks requis |
| marketplace | public | main | policy, security, node, python | 2 checks requis |
| desk | privé | main | policy, security, rust, node, shell | impossible (plan Free) |
| home-stock | privé | main | policy, security, python | impossible (plan Free) |
| design | privé | main | policy, security | impossible (plan Free) |

Les cinq dépôts publics refusent le push direct sur `main`, vérifié en
conditions réelles sur chacun. Les trois privés reçoivent la CI, Dependabot et
les fichiers de santé, mais aucune règle serveur : le plan Free ne le permet
pas, et cette asymétrie était assumée dès le § 3 du spec.

Toutes les branches par défaut s'appellent `main` : `shell` et `home-stock`
ont été renommés.

## Les règles, telles qu'elles s'appliquent réellement

**Anglais dans le code** — ne juge que les **lignes ajoutées ou modifiées**.
La granularité fichier du plan initial faisait qu'un commentaire d'une ligne
dans un fichier ancien exigeait de le traduire entièrement.

**500 lignes par fichier** — juge le fichier entier, une longueur ne se
mesurant pas partiellement. Échappement `policy: allow-long-file`, qui impose
d'éditer le fichier et apparaît donc en revue.

**Conventional Commits** — vérifie les commits de la pull request **et son
titre**, puisque le merge en squash fait du titre le message qui atterrit sur
`main`.

**Secrets** — gitleaks sur la plage de la pull request, sur les huit dépôts
indifféremment de leur visibilité. Un audit historique complet a été mené
séparément le 27 août.

## Ce que les adoptions ont trouvé

Le socle a été corrigé neuf fois, chaque fois parce qu'un dépôt réel l'a mis en
défaut :

| Correction | Ce qu'elle empêchait |
|---|---|
| `--diff-filter=ACMR` | un `git mv` blanchissait n'importe quel fichier |
| Expressions via `env:` | le nom de branche d'une PR était injecté dans un script shell |
| Binaire gitleaks | l'action officielle est payante pour les organisations |
| 16 homographes retirés | le contrôle refusait des commentaires anglais |
| Portée de `ruff` | 85 fichiers à reformater sur trois dépôts, rouges dès l'adoption |
| `pytest` exit 5 | tout dépôt sans suite pytest devenait rouge |
| Allowlist gitleaks | le socle attrapait sa propre documentation |
| Seuil `cargo audit` | une crate non maintenue bloquait un merge |
| `python-version` sur l'audit | `pip-audit` ne résolvait pas un manifeste exigeant 3.14 |
| `pip-audit` hors `pipx` | `pipx` ignorait l'interpréteur choisi, annulant la correction précédente |

Trois de ces corrections partagent la même forme : le socle imposait un défaut
qu'un dépôt ne pouvait pas utiliser. La réponse a chaque fois été d'exposer
l'hypothèse comme une entrée, avec l'ancien comportement pour valeur par
défaut.

Côté dépôts, la CI a révélé ce qu'aucune relecture n'aurait vu :

- **`shell`** : trois fichiers de tests jamais exécutés par aucun job, dont un
  cassé depuis des mois ; la couverture e2e et le lint zsh disparaissaient
  silencieusement avec l'ancien workflow, dont le test garantissant qu'une
  désinstallation laisse `HOME` intact.
- **`installer`** : des tests important cinq paquets que rien ne déclarait ; un
  bug de syntaxe dans un script de stress, où une redirection à l'intérieur des
  crochets rendait une comparaison inopérante ; douze fichiers nommés `test_*`
  qu'aucun lanceur ne peut exécuter.
- **`mqtt`** : une dépendance déclarée et jamais importée, portant l'unique
  vulnérabilité haute ; trois scripts vides ; un script qui n'avait jamais pu
  s'analyser depuis son commit initial.
- **`marketplace`** : un script `lint` appelant un eslint absent.
- **`home-stock`** : une suite de tests confinée à son conteneur, faute de
  chemin d'import, de manifeste et de la bonne version de Python.
- **`desk`** : 34 vulnérabilités hautes portées par des paquets qu'un graphe de
  modules mort était seul à importer.

## Limites connues

**CodeQL ne couvre pas `shell`.** Le § 6.4 du spec annonce une analyse CodeQL
sur `installer` et `shell`. CodeQL ne prend en charge ni Bash ni Zsh : sur
`shell`, l'analyse serait vide. `shellcheck -S warning` sur tout l'arbre et
`zsh -n` sur les sources zsh y tiennent lieu, tous deux actifs. Le spec
surestime la couverture sur ce point.

**Le job Rust de `desk` est rouge.** 133 de ses 159 fichiers ne passent pas
`cargo fmt --check`. Reformater dans une pull request d'infrastructure aurait
écrasé `git blame` sur la majeure partie du code Rust ; la dette est suivie en
issue `nivuus/desk#2`.

**Deux jobs privés restent rouges, délibérément.** Le job `rust` de `desk`
(formatage) et les jobs `python` et `security` de `home-stock` (dépendances
optionnelles de Home Assistant, et trois vulnérabilités dans `cryptography`
tirée transitivement). Ces trois dépôts étant privés, le plan Free interdit la
protection de branche : ces échecs ne bloquent aucun merge, et rendent la dette
visible, ce qui était le but.

**`desk` porte 46 détections gitleaks dans son historique**, relevées lors de
l'audit du 27 août : des journaux de sessions d'authentification, dont deux JWT
à haute entropie. Le dépôt est privé, l'exposition limitée aux collaborateurs.
La vérification des jetons et un éventuel nettoyage d'historique relèvent du
propriétaire.

## Dettes suivies

| Dépôt | Issue |
|---|---|
| shell | #5 benchmark en CI · #6 `manifest.sh` · #7 commentaires français · #8 structure des tests e2e |
| installer | #3 douze fichiers `test_*` inexécutables |
| desk | #2 formatage Rust · #3 code JavaScript mort |
| home-stock | #2 dépendances optionnelles de Home Assistant · #3 vulnérabilités `cryptography` |

## Pour un nouveau dépôt

Créer `.github/workflows/ci.yml` appelant `policy` et `security`, plus le
workflow de langage voulu, puis lancer
`scripts/apply-org-config.sh nivuus/<dépôt>`. Le `README.md` du socle en donne
le détail.
