# devcontainer

## À quoi ça sert

Deux images de dev container pour lancer Claude Code en mode autonome
(`--dangerously-skip-permissions`) sur mes projets perso sans surveiller chaque
appel d'outil.

Le principe : **le container est la barrière de sécurité**, pas le jugement de
l'agent. À l'intérieur, l'agent a carte blanche ; ce qui sort du container est
borné par construction — pas de credential cloud, pas de socket Docker, uid
non-root sans chemin vers root, et un garde-fou `PreToolUse` déposé root-only que
la session ne peut ni éditer ni désactiver.

Une exception, assumée et bornée : **un jeton GitHub entre dans le container**,
pour que l'agent puisse pousser une branche et ouvrir une pull request. Ce qu'il
permet n'est plus borné par construction mais par la portée du jeton, et ce qu'il
ne doit pas faire — pousser sur `main`, merger — l'est par la consigne. La
section « Ce que le garde-fou ne protège pas » le dit sans détour.

## Les deux images

| Image | Contenu |
|---|---|
| `ghcr.io/charlouze/devcontainer-agent-base` | Debian bookworm, utilisateur `dev`, durcissement, garde-fou, `mise` en user-level, CLI Claude, historique bash persistant, provisionnement |
| `ghcr.io/charlouze/devcontainer-web` | La précédente + node, pnpm, java (émulateurs Firebase) et les dépendances système des navigateurs Playwright |

Tags publiés : `1` (flottant sur la majeure, c'est celui à utiliser), `1.x.y`
(figé) et le sha du commit.

## Brancher un projet

```bash
claude plugin marketplace add charlouze/devcontainer
claude plugin install devcontainer@devcontainer
```

Puis, dans le dépôt à brancher :

```
/devcontainer-init
```

Un seul point d'entrée, quatre modes déduits de ce que le dépôt contient :

| Le dépôt… | Mode |
|---|---|
| a du code, pas de `.devcontainer` | brancher |
| a son propre `.devcontainer` d'avant ces images | migrer |
| est vide | amorcer — le container vient d'abord, le projet naît dedans |
| est déjà branché | mettre à jour |

Le plugin est aussi installé d'office dans les containers, mais il est fait pour
être installé **sur le poste** : il doit pouvoir agir avant que le container
existe.

Pour brancher un dépôt à la main, le fichier de référence est
`plugin/skills/onboard-devcontainer/references/devcontainer.template.json` — ses
commentaires expliquent chaque réglage, y compris le préfixage des volumes
propres au projet, et font partie du livrable au même titre que le JSON. Il
reste dans tous les cas à ajouter une tâche `setup` au `mise.toml` du projet :
c'est le contrat entre l'image et le projet. `post-create.sh` la lance si elle
existe, et son absence n'est pas une erreur.

```toml
[tasks.setup]
description = "Provisionnement du projet"
run = "pnpm install --frozen-lockfile"
```

## Règles de garde-fou propres à un projet

Le garde-fou lit `${CLAUDE_PROJECT_DIR}/.devcontainer/guard-rules.json` s'il
existe :

```json
{
  "bash":  [{ "pattern": "\\bstripe\\s+", "flags": "i", "reason": "…" }],
  "paths": [{ "pattern": "fixtures/prod-.*\\.json$", "reason": "…" }]
}
```

**Ces règles ne peuvent qu'ajouter au socle, jamais s'y substituer.** Le fichier
est dans le workspace, donc éditable par l'agent — la garantie tient par
construction et non par permission : le socle est évalué en premier et sort en
code 2 avant que le fichier projet soit seulement lu. Le supprimer ou le vider ne
lève donc aucun interdit, et y écrire une regex à backtracking catastrophique
pour faire expirer le hook ne peut neutraliser que les règles projet.

Tolérance aux erreurs : fichier absent, illisible, supérieur à 64 Ko, JSON
invalide, plus de 100 règles, ou regex non compilable → avertissement sur stderr
et on continue avec le socle. Ni fail-open silencieux, ni blocage total sur une
erreur de configuration.

## Pousser et ouvrir des PR

Le container peut pousser une branche et ouvrir une pull request. Il ne merge
pas : l'intégration se fait dans l'interface GitHub.

Le jeton est un **PAT fine-grained** à dépôts sélectionnés, avec `Contents` et
`Pull requests` en écriture, `Metadata` en lecture. **Ni `Administration`, ni
`Workflows`** — sans cette dernière, GitHub refuse lui-même tout push qui touche
`.github/workflows/`, ce qui est la seule barrière vraiment structurelle du
dispositif.

Il n'entre ni par un fichier de l'hôte, ni par une variable d'environnement. La
connexion est un geste humain, fait une fois, dans un terminal du container :

```bash
gh auth login --with-token
```

puis coller le jeton et Ctrl-D. Il passe par stdin, donc il n'entre pas dans
l'historique de shell — qui est persistant ici, et que le garde-fou traite déjà
comme un secret.

Le volume `agent-gh` est monté sur `/home/dev/.config/gh`, l'emplacement par
défaut de `gh` : la connexion survit aux recréations, et vaut pour tous les
projets. Contrairement à `CLAUDE_CONFIG_DIR`, aucune variable n'est nécessaire —
il n'y a rien à détourner, donc rien qu'un IDE puisse ignorer en silence. Le
provisionnement recâble ensuite git sur `gh` (`gh auth setup-git`) et pose
l'identité de commit depuis `gh api user`.

Sans connexion, le provisionnement le dit et continue : le container est alors
celui d'avant, sans capacité de push. C'est aussi ce qui arrive quand le PAT
expire.

## Ce qui persiste d'une recréation à l'autre

Le volume `agent-claude` est monté sur `/home/dev/.claude` et porte la connexion,
les réglages et les plugins. Mais le fichier de configuration principal de Claude
Code n'est pas dans ce répertoire : c'est `~/.claude.json`, un **frère** du
répertoire et non un enfant. Il portait donc l'onboarding, l'identité du compte
et la confiance du projet dans la couche inscriptible du container, où ils
mouraient à chaque recréation.

Le contre-intuitif : **persister le jeton ne suffisait pas**. `.credentials.json`
est bien dans le volume et survit vraiment, mais l'identité vit dans
`oauthAccount`, côté `.claude.json`. Le container revenait donc jeton valide et
identité inconnue — et le flux de première connexion rejouait malgré le jeton.

Depuis la `1.2.0`, l'image pose `CLAUDE_CONFIG_DIR=/home/dev/.claude` : le
fichier atterrit dans le volume, à côté des credentials qu'il rend utilisables.
La variable est dans l'**image** et non dans le `containerEnv` du projet, parce
qu'un `containerEnv` ignoré par l'IDE reviendrait vide et ferait retomber Claude
Code sur `$HOME` sans qu'aucune erreur ne le signale.

**Le premier rebuild après la montée en `1.2.0` rejoue l'onboarding une dernière
fois**, l'ancien fichier ayant disparu avec l'ancien container. Pour l'éviter,
depuis le container encore en cours et *avant* de reconstruire :

```bash
cp -p ~/.claude.json ~/.claude/.claude.json
```

`-p` n'est pas décoratif : le fichier est en mode 600 et porte l'identité du
compte.

**Le volume de login est partagé entre projets**, à dessein — et l'écriture
concurrente y est sûre, pour une raison qui vaut d'être dite. Deux containers
ouverts en même temps écrivent le même fichier, exactement comme deux terminaux
ouverts sur un poste : c'est le cas ordinaire de Claude Code, pas une situation
que la conteneurisation invente. L'écriture passe par un verrou inter-processus
et relit la configuration sur disque avant d'écrire, lu dans le binaire plutôt
qu'éprouvé ici avec deux containers réellement concurrents.

Ce verrou se pose **à côté du fichier qu'il protège**. Avant la `1.2.0`, la
configuration vivant hors du volume, chaque container avait donc son fichier
*et son verrou* : deux instances qui ne se voyaient pas. En déplaçant le fichier
dans le volume, on y déplace le verrou — le partage n'est pas toléré malgré la
concurrence, il est correct parce que la concurrence devient visible.

**Une configuration corrompue survit désormais aussi.** Ce fichier se corrompt en
pratique ; jusqu'ici la couche inscriptible l'effaçait au rebuild suivant, par
accident. Si un container reconstruit repart sur un onboarding vierge, regarder
`~/.claude/backups/` avant de se reconnecter : Claude Code y tient des copies
`.claude.json.backup.*`, et y met en quarantaine ce qu'il n'a pas su relire.

**Le cache Playwright est partagé entre projets, et l'image y désactive le
ramassage automatique des navigateurs.** Le volume `agent-playwright` est monté
sur `/home/dev/.cache/ms-playwright` : un navigateur téléchargé par un projet
sert à tous. Mais ce cache n'est pas content-addressed comme le store pnpm, il
est **compté par références** — chaque `playwright install` y écrit, dans
`.links/`, le chemin absolu du paquet `playwright-core` qui installe, puis
supprime tout navigateur qu'aucun de ces liens ne réclame plus. Or d'un
container à l'autre, le chemin du projet voisin n'existe pas : son lien est
déclaré cassé et ses navigateurs partent avec. Chaque provisionnement vidait
ainsi le cache de tous les autres projets, qui retéléchargeaient au test
suivant. L'image pose désormais `PLAYWRIGHT_SKIP_BROWSER_GC=1`.

La contrepartie est assumée : **le volume ne se purge plus jamais tout seul**.
Une version de Playwright abandonnée y laisse ses navigateurs, de l'ordre de
500 Mo par version avec chromium et webkit. Pour le remettre à plat, depuis
n'importe quel container :

```bash
pnpm exec playwright uninstall --all
```

La commande ignore délibérément la variable ; le `setup` de chaque projet
retéléchargera ce dont il a besoin.

## Recevoir une nouvelle version

Le template épingle le tag flottant `:1`, à dessein : l'invariant `image-tag`
refuse un tag figé, pour qu'un projet suive les correctifs sans qu'on repasse
sur son `devcontainer.json` à chaque publication.

Le coût est là, et il est silencieux : **Docker ne re-télécharge pas un tag dont
il détient déjà une copie locale**. Une version publiée n'atteint donc pas un
poste qui a déjà tiré l'image. Le container se recrée — sur l'ancienne, sans
qu'aucun message ne le signale. Avant de reconstruire :

```bash
docker pull ghcr.io/charlouze/devcontainer-web:1
```

`-web` ou `-agent-base` selon l'image du projet. Puis recréer le container : un
`pull` sans recréation ne change rien, l'image en cours d'exécution reste celle
sur laquelle le container a été créé.

C'est aussi ce qui rend le `cp -p` de la section précédente inopérant si on
l'applique sans rafraîchir : le fichier est bien recopié, mais le container
repart sur une image qui ne pose pas `CLAUDE_CONFIG_DIR`, et l'état meurt comme
avant.

## Publier une version

Avant de taguer, aligner la version du plugin sur celle des images, dans
`.claude-plugin/marketplace.json` et `plugin/.claude-plugin/plugin.json`. Sur un
changement de majeure, mettre aussi à jour le tag du template
(`plugin/skills/onboard-devcontainer/references/devcontainer.template.json`) :
`tests/unit/plugin-manifests.test.cjs` échoue tant que les deux divergent.

Ne pose le tag qu'une fois `.claude-plugin/marketplace.json` présent sur
`main` avec cette version : le plugin est déclaré dans `plugins.d`, donc
chaque container tente de l'installer au provisionnement, et tant que la
marketplace publiée ne le contient pas, `install-plugins.sh` affiche un
avertissement à chaque fois.

Le dépôt s'applique ses propres règles : branche, pull request, merge dans
l'interface. Le tag ne se pose qu'ensuite, sur `main` à jour — l'ordre compte,
`main` devant porter la marketplace à la bonne version avant que le tag
n'existe.

```bash
git checkout main && git pull
git tag v1.3.0 && git push origin v1.3.0
```

Un tag n'est pas une branche : une ruleset qui cible la branche par défaut ne
s'oppose pas à son push.

Le workflow construit les deux images, rejoue les tests unitaires **et le smoke
test contre les images construites**, et ne publie qu'ensuite. Un échec n'atteint
jamais le tag flottant `1`, sur lequel pointent tous les projets.

En local, `mise run check` rejoue exactement la même séquence. Sous Windows, à
lancer depuis Git Bash : dans PowerShell, `bash` résout vers le lanceur WSL.

## Ce que le garde-fou ne protège pas

Un garde-fou dont on ignore les limites donne une confiance qu'il ne mérite pas.

- **Le jeton d'authentification de l'agent est lisible depuis la session.** Une
  règle qui prétendrait en interdire la lecture serait décorative.
- **L'agent peut commiter localement et modifier n'importe quel fichier du
  workspace.** Il peut aussi pousser une branche, ouvrir et modifier une PR,
  suivre la CI (`gh pr checks`, `gh run watch`) et lire le dépôt (`gh repo view`,
  `gh search`, `gh browse`…). Restent bloqués : `firebase deploy`, `npm publish`,
  tout `gcloud`, et les commandes `gh` hors lecture et PR — `gh pr merge`,
  `gh pr close`, `gh api` et `gh auth login` compris. La liste blanche du
  garde-fou nomme aussi `gh issue`, mais le PAT n'a pas la permission `Issues` :
  GitHub répondrait 403. Le garde-fou est la limite la plus molle des deux, donc
  la laisser plus large que le jeton ne coûte rien.
- **`main` et le merge ne sont protégés que par la consigne.** Le garde-fou
  refuse `git push origin main` et `gh pr merge`, mais le jeton GitHub est
  lisible depuis la session et l'API est joignable : un appel direct passerait.
  C'est un choix, pas un oubli — les garanties dures sont la portée du PAT et les
  permissions qu'il n'a pas. Une ruleset sur `main` referme le premier point là
  où GitHub l'accepte ; l'onboarding la tente.
- **Un `git push` sans argument depuis `main` échappe au garde-fou**, comme
  `git push --force` sans argument. La règle ne lit que la ligne de commande et
  ne connaît pas la branche courante : elle ne voit ni `main` ni de refspec, donc
  elle laisse passer. C'est la forme la plus probable de l'accident, puisque
  c'est ce qu'on tape après un `-u`. La bloquer casserait le flux de branche
  normal ; seule une ruleset côté GitHub ferme vraiment ce trou.
- **Le volume `agent-gh` est partagé entre projets**, donc tout container peut
  pousser sur tous les dépôts que le PAT couvre. Même portée que `.claude.json`,
  déjà partagé.
- **L'accès réseau sortant n'est pas filtré.**
- **Les règles projet sont supprimables**, puisqu'elles vivent dans le workspace.
  D'où le fait qu'elles ne soient qu'additives.
- **Le workspace ne vit que dans un volume Docker**, pas sur le disque de
  l'hôte — et **il ne survit pas à la recréation du container**. Le plugin dev
  container de JetBrains crée un volume de sources neuf à chaque recréation et
  re-clone depuis le distant (observé le 2026-08-15) ; c'est aussi ce qui permet
  d'ouvrir le même dépôt dans plusieurs containers à la fois, donc ce n'est
  probablement pas un comportement passager. Conséquence : ce qui n'a pas été
  poussé disparaît, **commits locaux compris, et sur un rebuild parfaitement
  réussi** — pas seulement sur un accident. Les volumes ainsi laissés orphelins,
  un `docker volume prune` ou une remise à zéro de Docker Desktop achèvent le
  reste, et aucune sauvegarde de l'hôte ne les couvre. La fenêtre s'est
  resserrée depuis que le container peut pousser : c'est maintenant à portée de
  l'agent, et une branche poussée est la seule copie qui survit au volume.
- **Le volume de login est partagé entre projets, donc `.claude.json` aussi.**
  Le container d'un projet peut lire la configuration MCP d'un autre —
  `mcpServers` porte couramment des clés d'API tierces dans ses blocs `env` —
  ainsi que son historique de prompts. Le jeton OAuth était déjà partagé ; c'est
  une portée de lecture nouvelle, pas un nouveau principe.
