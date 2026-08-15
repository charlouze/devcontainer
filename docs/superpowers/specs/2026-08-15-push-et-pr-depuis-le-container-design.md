# Pousser et ouvrir des PR depuis le container

Date : 2026-08-15
État : design validé, prêt pour la planification d'implémentation

## 1. Objectif

Autoriser l'agent à **pousser des branches** et à **ouvrir et modifier des pull
requests** depuis le container. Le merge reste un geste humain, fait dans
l'interface GitHub.

Et, au passage, distribuer à tous les projets deux conventions d'écriture que ce
dépôt applique déjà à lui-même : aucune mention d'assistant dans les messages de
commit, et des corps de PR dont les paragraphes tiennent sur une seule ligne.

Le besoin vient de l'usage. Le garde-fou bloque `git push` depuis l'origine, ce
qui obligeait à sortir du container pour publier le moindre travail — et rendait
la perte du workspace d'autant plus probable qu'elle est déjà documentée comme
certaine à chaque recréation.

## 2. Ce que ça change au modèle de sécurité

Le principe affiché du dépôt change, et il faut le dire franchement plutôt que
de le laisser se périmer en silence.

**Avant** : aucun credential n'entre dans le container. « Pas de publication »
tient alors *par construction* — le garde-fou peut être contourné, la commande
échoue quand même, faute de quoi s'authentifier.

**Après** : un jeton est présent. Tout ce que ce jeton permet devient atteignable
par un simple `curl` sur l'API, sans passer ni par `git` ni par `gh`. Le
garde-fou n'empêche donc plus que **l'accident et la facilité**, jamais la
volonté. C'est la même honnêteté que le README applique déjà au jeton de l'agent,
dont il dit qu'une règle prétendant en interdire la lecture serait décorative.

Ce qui reste structurel, et ce qui devient conventionnel :

| Garantie | Nature | Tenue par |
|---|---|---|
| Le container n'atteint que les dépôts choisis | Structurelle | Portée du PAT, côté GitHub |
| Aucun push ne peut toucher `.github/workflows/` | Structurelle | Permission `Workflows` non accordée : GitHub refuse le push lui-même |
| Le jeton ne peut pas modifier les réglages du dépôt | Structurelle | Permission `Administration` non accordée |
| Pas de push sur `main` | Conventionnelle | Garde-fou et consigne |
| Pas de merge | Conventionnelle | Garde-fou et consigne |

Les deux dernières lignes sont une **décision assumée**, prise en connaissance de
cause. Les rendre structurelles supposait soit une ruleset GitHub (dont la
disponibilité sur un dépôt privé en plan gratuit n'est pas acquise, et qu'on ne
paiera pas), soit une identité distincte pour le container — compte machine ou
GitHub App — dont le coût de gestion excède le risque encouru sur des projets
personnels. Voir §3 pour le détail des variantes écartées.

Deux compensations gratuites sont retenues :

- **Le PAT ne reçoit ni `Administration` ni `Workflows`.** L'absence de
  `Workflows` est la seule barrière vraiment dure de tout ce design, et elle
  couvre le seul endroit où un dégât serait durable : la CI.
- **La skill d'onboarding tente de poser une ruleset** sur la branche par défaut
  (PR obligatoire, pas de suppression, pas de non-fast-forward, `bypass_actors`
  vide). Elle est créée depuis le poste avec le `gh` de l'humain — le PAT du
  container n'a pas la permission de le faire, et c'est voulu : il ne doit pas
  pouvoir défaire ce qui l'encadre. Si GitHub refuse, on le dit et on continue.
  Gratuit là où ça marche, jamais bloquant.

`bypass_actors` doit rester **vide**, y compris du rôle « administrateur du
dépôt » : le PAT agit au nom de son propriétaire, donc tout bypass accordé à ce
rôle serait hérité par le container et rendrait la ruleset décorative. La
conséquence à accepter est que l'humain non plus ne pousse plus sur `main` — ce
qui est précisément l'intention, mais qui change la procédure de publication de
*ce* dépôt-ci, aujourd'hui documentée comme `git push origin main --tags`.

Bénéfice collatéral, à répercuter dans le README : la section « le workspace ne
survit pas à la recréation du container » perd l'essentiel de son mordant. La
fenêtre de perte était longue *parce que* seul l'humain pouvait publier ; elle se
referme.

## 3. Le credential : forme et circulation

**Un PAT fine-grained unique**, à dépôts sélectionnés, partagé par tous les
containers. Permissions : `Contents` lecture/écriture, `Pull requests`
lecture/écriture, `Metadata` lecture seule. Ni `Administration`, ni `Workflows`.

Un jeton par projet aurait réduit le rayon de souffle à un dépôt, au prix d'un
PAT à créer et à renouveler par projet. Le choix suit celui déjà fait pour le
volume de login : partagé à dessein, parce que le coût d'entretien d'un secret
par projet se paie à chaque projet et que le gain reste théorique sur des dépôts
personnels.

**Le jeton n'entre ni par un fichier de l'hôte, ni par une variable
d'environnement.** La connexion est un geste humain, fait une fois, dans un
terminal de container :

```
gh auth login --with-token
```

puis coller le PAT et Ctrl-D. Le jeton passe par stdin : il n'apparaît donc dans
aucune ligne de commande, et n'entre pas dans l'historique de shell — qui est
persistant ici, et que le garde-fou traite déjà comme un secret.

**La persistance passe par un volume dédié** `agent-gh`, monté sur
`/home/dev/.config/gh`, soit l'emplacement par défaut de `gh`. Le préfixe
`agent-` le range dans la famille documentée des volumes partagés entre projets :
se connecter une fois, pour tous les containers présents et futurs.

Le point important est ce qu'on n'a **pas** eu à faire. `CLAUDE_CONFIG_DIR`
existe parce que Claude Code range son fichier principal hors du répertoire qu'on
peut monter : il fallait détourner un chemin, donc introduire une variable, donc
accepter le risque qu'un IDE cessant de l'honorer produise une panne muette.
`gh` cherche déjà au bon endroit — on y monte un volume, et il n'y a ni variable
à poser, ni chemin à tenir en accord, ni panne silencieuse possible.

`/home/dev/.config/gh` est créé dans l'image avec le bon propriétaire, pour la
raison déjà écrite au-dessus des autres points de montage : un chemin absent de
l'image donne un point de montage `root:root`, où `dev` ne peut rien écrire — et
`gh auth login` échouerait.

### Alternatives écartées

| Option | Raison du rejet |
|---|---|
| `~/.claude/gh` via `GH_CONFIG_DIR` | Range l'état d'un outil dans le répertoire d'un autre, et fait tenir la cohabitation par une variable d'environnement là où un volume au bon endroit suffit |
| Fichier de jeton sur l'hôte, monté en lecture seule | Une copie de plus, un renouvellement par poste, et le piège du bind mount dont la source n'existe pas — Docker crée alors un *répertoire* à sa place |
| `GH_TOKEN` par `containerEnv`/`localEnv` | C'est le jeton OAuth complet du poste, tous dépôts et tous scopes. Et l'outil Bash de l'agent n'est ni interactif ni un shell de login : ni `/etc/profile.d` ni `/etc/bash.bashrc` n'y sont lus, seul un `ENV` d'image traverse — et il ne peut pas porter une valeur lue à l'exécution |
| Agent SSH forwardé depuis l'hôte | Ne couvre que `git` : `gh` réclame un jeton HTTP de toute façon. Et le forwarding depuis Windows via le plugin JetBrains est le point fragile |
| Compte machine dédié, ou GitHub App | Seule voie pour rendre le merge structurellement humain : la ruleset peut alors exiger une approbation que le container ne peut pas donner. Écartée pour son coût — un second compte à inviter dépôt par dépôt et un historique signé par un bot, ou une clé privée qui ne peut pas entrer dans le container et un jeton d'installation d'une heure à réémettre côté hôte |

## 4. Câblage dans le container

`gh auth setup-git` configure git pour prendre `gh` comme credential helper : un
seul mécanisme d'authentification pour les deux outils, et aucune variable
d'environnement dans la boucle. `~/.gitconfig` n'étant sous aucun volume,
`post-create.sh` le refait à chaque provisionnement — l'opération est idempotente
et c'est sa place.

**L'identité git est dérivée de `gh api user`** : `user.name` depuis le nom
public (repli sur le login), `user.email` sur la forme
`<id>+<login>@users.noreply.github.com`. Aujourd'hui *rien* ne pose cette
identité — un défaut latent que seul le push rend visible, puisque sans
`user.email` le premier commit échoue.

**Dégradation gracieuse** : sans connexion `gh`, le provisionnement affiche
`GitHub : non connecté — gh auth login --with-token` et continue. Le container
est alors exactement celui d'aujourd'hui, sans capacité de push. C'est aussi
l'état de tout container recréé après l'expiration du PAT.

Le nouveau `lib/github-auth.sh` porte ces trois choses ; `post-create.sh` l'appelle
comme les autres, et met à jour son message de fin pour dire ce qui est désormais
autorisé.

**`gh` n'est installé dans aucune des deux images.** Il est ajouté à
`agent-base`, en user-level (`mise use --global --yes gh@latest`), sur le modèle
de ce que fait déjà l'image `web` pour node, pnpm et java. Repli sur le dépôt apt
de GitHub CLI si le backend `mise` s'avère capricieux — à trancher à
l'implémentation, pas ici.

## 5. Le garde-fou

Il devient une barrière molle (§2) et doit être écrit comme tel. Ce qu'il change :

| Règle | Avant | Après |
|---|---|---|
| `git push` | Bloqué en bloc | Autorisé, **sauf** `main`/`master` nommés sous toutes leurs formes (`origin main`, `HEAD:main`, `refs/heads/main`), et sauf `--all`, `--mirror`, `--tags`, `--delete` |
| `gh` | Liste noire de cinq sous-commandes | **Liste blanche** par lookahead négatif : `pr create\|edit\|view\|list\|diff\|status\|checkout\|comment\|ready`, plus quelques lectures (`issue`, `repo view`, `auth status`). Tout le reste refusé par défaut |

`--force` reste autorisé sur une branche : c'est le cas normal après un rebase,
et le cas dangereux est couvert par le nom de la branche. La limite est assumée
et consignée au §10 : `git push --force` sans argument, depuis `main`, n'est pas
détectable par une règle qui ne lit que la ligne de commande.

La liste blanche `gh` a une propriété que la liste noire n'avait pas : elle
refuse **les sous-commandes futures** et `gh api`, qui contournerait n'importe
quelle énumération. `pr merge` et `pr close` en sortent nommément exclus.

Restent inchangés : `firebase deploy`, `gcloud`, `npm publish`, la modification
des remotes et de la config git globale. Cette dernière mérite une note : le
provisionnement s'en sert (§4) sans que ce soit une contradiction — le garde-fou
n'inspecte que les appels d'outils de la session, pas les scripts de cycle de vie.

**Aucune règle n'est ajoutée sur le chemin du jeton ni sur `curl`.** Elles
seraient décoratives, au sens exact où ce dépôt refuse déjà les règles
décoratives. Leur place est dans « ce que le garde-fou ne protège pas ».

## 6. Les conventions distribuées

Le contenu vit dans l'image, en `/etc/devcontainer/conventions.md`, root-only et
en 0444. Il porte quatre consignes : pas de mention d'assistant dans les messages
de commit (`Co-Authored-By`, `Claude-Session`, « Generated with »), des corps de
PR dont les paragraphes tiennent sur une seule ligne, pas de push sur `main`,
pas de merge.

Le rattachement se fait par une ligne `@/etc/devcontainer/conventions.md` ajoutée
au `CLAUDE.md` du volume partagé **si elle n'y est pas déjà**. L'ajout est
idempotent et n'écrase jamais : le volume est partagé et peut porter les mémoires
propres de l'utilisateur. Ranger le contenu dans l'image plutôt que dans le
volume lui fait suivre les versions de l'image, au lieu de se figer au jour où le
volume a été créé.

**Instruction seule, rien de mécanique.** Un hook `commit-msg` root-only posé par
`core.hooksPath` avait été proposé : il aurait rattrapé la mention d'assistant
quel que soit le chemin — `-m`, `-F`, héredoc ou éditeur. Il est écarté au profit
de la simplicité et de l'absence de faux positifs : rendre impossible d'écrire
« Claude » dans un message de commit gêne aussi les cas légitimes. Le coût est
assumé : un agent distrait passe outre, et c'est un défaut de discipline, pas une
faille.

## 7. Template et onboarding

Le template gagne une ligne, et rien d'autre :

```
"source=agent-gh,target=/home/dev/.config/gh,type=volume"
```

La skill d'onboarding gagne une étape « credentials GitHub », qui tourne **sur le
poste** — ce pour quoi le plugin est fait :

1. Créer le PAT fine-grained sur github.com, avec la liste de permissions du §3
   et son avertissement (ni `Administration`, ni `Workflows`).
2. Se connecter une fois dans le container (`gh auth login --with-token`).
3. Tenter la ruleset : `GET /repos/{owner}/{repo}/rulesets` pour l'idempotence,
   puis `POST` si absente ; signaler une ruleset homonyme divergente sans la
   modifier ; traiter un refus de GitHub comme une information, pas comme un
   échec de branchement.

Ces appels passent par `gh api`, que le garde-fou refuse (§5) — sans
contradiction : ils sont émis depuis le poste, avec le `gh` de l'humain, jamais
depuis le container. C'est la même séparation que pour la permission
`Administration`, que le PAT n'a pas.

Le mode « mettre à jour » doit savoir ajouter le montage `agent-gh` aux projets
déjà branchés. Les fixtures `tests/fixtures/onboarding/*/attendu/devcontainer.json`
suivent.

## 8. Vérifications

| Ce qui est vérifié | Par quoi |
|---|---|
| Les formes de `git push` autorisées et refusées | `tests/unit/rules.test.cjs` |
| La liste blanche `gh`, y compris son refus par défaut d'une sous-commande inconnue | `tests/unit/rules.test.cjs` |
| Le montage `agent-gh` est présent et pointe sur le chemin par défaut de `gh` | Invariant dans `tests/lib/devcontainer-invariants.cjs` |
| Les fixtures d'onboarding portent le nouveau montage | `tests/unit/fixtures-onboarding.test.cjs` |
| `gh` est présent et exécutable dans les deux images | `tests/smoke.sh` |
| Le provisionnement sans connexion `gh` n'échoue pas | `tests/smoke.sh` |
| L'import des conventions est ajouté une fois et une seule | `tests/smoke.sh`, en rejouant le provisionnement |

Le comportement de `gh auth login` lui-même n'est pas testé : il demande un jeton
valide, donc une session authentifiée, donc rien qui puisse vivre en CI. Comme
pour la connexion de Claude Code, la vérification est manuelle et le smoke test
se limite à la plomberie — ce que le commentaire du test doit dire, pour ne pas
donner une fausse assurance.

## 9. Versionnage

Version mineure : `1.3.0`. Un projet déjà branché continue de fonctionner sans le
nouveau montage — il perd seulement la persistance de la connexion `gh`, qu'il
n'avait pas avant. Le template reste sur le tag `:1` ; la règle du README sur le
tag du template ne concerne que les majeures.

`plugin/.claude-plugin/plugin.json` et `.claude-plugin/marketplace.json` sont
alignés sur cette version, comme le vérifie `tests/unit/plugin-manifests.test.cjs`.

## 10. Limites assumées

- **Le jeton est lisible depuis la session.** Il l'est au même titre que celui de
  l'agent, et pour la même raison : aucune règle ne peut l'en empêcher sans être
  décorative.
- **Le push sur `main` et le merge ne sont pas empêchés structurellement.** Le
  garde-fou les refuse, l'API les accepterait.
- **Le volume est partagé, donc tout container peut pousser sur tous les dépôts
  couverts par le PAT.** C'est le prolongement exact de la portée déjà documentée
  pour `.claude.json`, pas un principe nouveau.
- **`git push --force` sans argument depuis `main` échappe à la règle**, qui ne
  lit que la ligne de commande et ne connaît pas la branche courante.
- **L'expiration du PAT se manifeste comme une déconnexion**, à traiter à la main
  par un nouveau `gh auth login`.
- **La disponibilité des rulesets de dépôt sur un dépôt privé en plan gratuit
  n'est pas confirmée.** La documentation consultée le 2026-08-15 ne porte de
  restriction de plan que sur les rulesets *d'organisation*, mais elle ne dit rien
  d'explicite sur les rulesets de dépôt. D'où la tentative opportuniste plutôt
  qu'un prérequis.

## 11. Ce que le README doit dire

- Le principe affiché passe de « aucun credential n'entre » à « un credential
  borné entre, et voici ce qu'il permet », avec la distinction structurel /
  conventionnel du §2.
- Une section « pousser et ouvrir des PR » : le PAT et ses permissions, la
  connexion unique, le volume `agent-gh`.
- « Ce que le garde-fou ne protège pas » gagne le push sur `main`, le merge, et
  la lisibilité du jeton GitHub.
- La section sur le workspace qui ne survit pas à la recréation est révisée :
  publier redevient possible depuis le container, la fenêtre se referme.
- La procédure de publication de ce dépôt change si une ruleset est posée sur son
  propre `main` : branche, PR, merge dans l'interface, puis le tag.
