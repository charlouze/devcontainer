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

## Publier une version

Avant de taguer, aligner la version du plugin sur celle des images, dans
`.claude-plugin/marketplace.json` et `plugin/.claude-plugin/plugin.json`. Sur un
changement de majeure, mettre aussi à jour le tag du template
(`plugin/skills/onboard-devcontainer/references/devcontainer.template.json`) :
`tests/unit/plugin-manifests.test.cjs` échoue tant que les deux divergent.

```bash
git tag v1.0.0
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
