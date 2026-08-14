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
avertissement à chaque fois. Rare en pratique puisque `git push origin main
--tags` ci-dessous pousse les deux ensemble, mais l'ordre compte si le push
est fait en deux temps.

```bash
git tag v1.2.0
git push origin main --tags
```

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
  workspace.** Seule la *publication* est bloquée : `git push`, `firebase deploy`,
  `npm publish`, les commandes `gh` qui écrivent, tout `gcloud`.
- **L'accès réseau sortant n'est pas filtré.**
- **Les règles projet sont supprimables**, puisqu'elles vivent dans le workspace.
  D'où le fait qu'elles ne soient qu'additives.
- **Le workspace ne vit que dans un volume Docker**, pas sur le disque de
  l'hôte. Un `docker volume prune`, une remise à zéro de Docker Desktop ou un
  volume orphelin après un rebuild raté emporte le travail non poussé, et aucune
  sauvegarde de l'hôte ne le couvre. La fenêtre est plus longue ici qu'ailleurs :
  le garde-fou bloque `git push`, donc c'est l'humain qui publie, et rien ne le
  fait à sa place.
- **Le volume de login est partagé entre projets, donc `.claude.json` aussi.**
  Le container d'un projet peut lire la configuration MCP d'un autre —
  `mcpServers` porte couramment des clés d'API tierces dans ses blocs `env` —
  ainsi que son historique de prompts. Le jeton OAuth était déjà partagé ; c'est
  une portée de lecture nouvelle, pas un nouveau principe.
