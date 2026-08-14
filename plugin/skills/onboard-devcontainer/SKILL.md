---
name: onboard-devcontainer
description: À utiliser quand un dépôt doit recevoir un dev container, quand une configuration de dev container existante doit passer sur les images partagées ghcr.io/charlouze/devcontainer-*, quand un dépôt sans manifeste Node ni Firebase reconnu doit être amorcé, ou quand un dépôt déjà branché doit suivre une nouvelle version des images — notamment après /devcontainer-init.
---

# Onboarding d'un dev container

## Vue d'ensemble

Ce dépôt-ci publie deux images de dev container conçues pour faire tourner un
agent de code en mode YOLO (`--dangerously-skip-permissions`). Le container
**est** la barrière de sécurité : ce que l'agent ne doit pas pouvoir faire lui
est rendu impossible, pas déconseillé.

Cette skill branche un dépôt sur ces images. Elle ne génère aucune application :
`nx create-workspace` et `firebase init` ont leurs propres générateurs.

## Détection du mode

Regarde le dépôt cible dans cet ordre et arrête-toi au premier cas qui
correspond :

| Ce que contient le dépôt | Mode | À lire |
|---|---|---|
| `.devcontainer/devcontainer.json` dont l'`image` est `ghcr.io/charlouze/devcontainer-*` | mettre à jour | `references/mettre-a-jour.md` |
| un `.devcontainer/` d'une autre facture (`Dockerfile`, `post-create.sh`, `agent-guard.cjs`, ou un `devcontainer.json` qui construit son image) | migrer | `references/migrer.md` |
| ni `package.json` ni `firebase.json` à la racine | amorcer | `references/amorcer.md` |
| du code, mais pas de `.devcontainer/` | brancher | `references/brancher.md` |

« Ni `package.json` ni `firebase.json` » veut dire : sans manifeste Node ni
Firebase reconnu — pas « sans aucun fichier ». Un dépôt Python ou Go bien
rempli, mais qui n'a ni l'un ni l'autre, tombe dans « amorcer » : c'est « vide »
au sens où cette skill n'a rien à y lire, pas au sens où le répertoire serait
sans contenu.

« Du code » à la dernière ligne n'est pas un critère à évaluer : c'est le cas
par défaut, appliqué par élimination à tout dépôt qui n'a matché aucune des
trois lignes précédentes — donc qui porte l'un des deux manifestes et n'a pas
de `.devcontainer/`.

Annonce le mode retenu et ce qui l'a déclenché avant d'agir. Si deux cas
semblent correspondre, demande — c'est le signe d'un dépôt à moitié migré, et se
tromper de mode y ferait perdre du travail.

## Règles communes à tous les modes

- **Le template est la source.** Pars toujours de
  `references/devcontainer.template.json` et remplace les marques `<…>`.
  N'écris jamais un `devcontainer.json` de mémoire.
- **Les commentaires du template sont un livrable.** Ils expliquent des réglages
  dont le symptôme, quand ils manquent, ne mène pas à la cause. Recopie-les.
  N'en retire un que si tu retires aussi le réglage qu'il explique.
- **Le tag d'image se recopie du template**, jamais d'ailleurs. Le plugin est
  versionné avec les images, donc ce tag existe. Un tag inventé donne un projet
  qui ne démarre plus.
- **Le slug** est le nom du répertoire du dépôt, en minuscules, tout caractère
  hors `[a-z0-9]` remplacé par `-`, tirets répétés fusionnés, tirets de début et
  de fin retirés. `Compte-de-Famille` → `compte-de-famille`.
- **Le nom lisible du projet** — celui qui remplace `<Nom du projet>` dans le
  template — se reprend tel qu'il apparaît dans le dépôt : le champ `name` de
  `package.json`, à défaut le nom du répertoire. Si `package.json` existe mais
  n'a pas de champ `name`, c'est le même défaut : le nom du répertoire.
  Aucune retouche de casse ni d'espacement : c'est mécanique, donc
  reproductible d'une exécution à l'autre, contrairement à une reformulation
  « telle qu'un humain l'écrirait ».
- **Rien n'est supprimé ni écrasé sans que le diff ait été montré** et validé.
  Vaut pour les fichiers comme pour les clés d'un fichier existant. Le gate
  s'applique à ce qui **écrase ou supprime du contenu existant**, jamais à la
  création d'un fichier qui n'existait pas : « brancher » et « amorcer »
  créent, ils n'ont rien à faire valider avant d'écrire ; « migrer » et
  « mettre à jour » écrasent, ils montrent le diff et attendent.
- **Le garde-fou ne se négocie pas.** Tu peux écrire un
  `.devcontainer/guard-rules.json`, qui ne fait qu'**ajouter** des interdits au
  socle. Tu ne touches à rien d'autre : le socle vit dans l'image, en root, et
  toute clé qui prétendrait le désactiver serait au mieux décorative.
- **Le contrat côté projet est `mise.toml`.** Le provisionnement d'un projet
  s'écrit dans une tâche `setup`, au même endroit que ses tâches de dev, pas
  dans un script shell du `.devcontainer`.

## Liste de contrôle finale

À passer sur le `devcontainer.json` produit, dans tous les modes, **avant**
d'annoncer que c'est fait. Chaque ligne est un invariant vérifié par ailleurs en
CI (`tests/lib/devcontainer-invariants.cjs` du dépôt `charlouze/devcontainer`) :
si tu en violes un, la faute se verra plus tard et coûtera plus cher.

- `image-tag` — l'image est `ghcr.io/charlouze/devcontainer-web:1` ou
  `…-agent-base:1` : une image du dépôt, sur un tag de majeure. Jamais un tag
  figé : un projet doit suivre les correctifs.
- `utilisateurs` — `containerUser` vaut `root` et `remoteUser` vaut `dev`. Le
  premier sert au chown du clone par JetBrains ; le second est celui sous lequel
  l'agent tourne, et tout le durcissement en dépend.
- `post-create` — `postCreateCommand` vaut exactement
  `/usr/local/share/devcontainer/post-create.sh`. Le script est fourni par
  l'image : un chemin dans le workspace serait éditable par l'agent.
- `runargs-securite` — `--security-opt no-new-privileges` et `--cap-drop ALL`
  sont présents, et les seules capabilities rendues sont `CHOWN`, `FOWNER`,
  `DAC_OVERRIDE`, `SETUID`, `SETGID`.
- `runargs-parser` — `runArgs` ne contient rien d'autre que `--security-opt`,
  `--cap-drop` et `--cap-add`. Le parser d'IntelliJ ne connaît qu'un
  sous-ensemble des options `docker run` et échoue sur les autres. Les plafonds
  CPU/RAM se règlent dans `%UserProfile%\.wslconfig`.
- `volumes` — les cinq montages sont là : `agent-claude`, `agent-pnpm-store` et
  `agent-playwright` partagés entre projets, `<slug>-cache` et `<slug>-history`
  propres au projet.
- `pas-de-socket-docker` — aucun montage `type=bind`, en particulier pas le
  socket Docker : ce serait une évasion en une commande.
- `pas-de-variable-garde-fou` — aucune variable d'environnement ne prétend
  activer ou désactiver le garde-fou. Il s'active sur la présence de
  `/etc/claude-guard/enabled`, root et non falsifiable, précisément parce que
  l'agent contrôle l'environnement des processus qu'il lance.
- `ports-libelles` — chaque port de `forwardPorts` a son entrée dans
  `portsAttributes`.

Termine en rappelant à l'humain ce que le garde-fou **ne** protège **pas** : le
jeton d'authentification de l'agent est lisible depuis la session, l'agent peut
commiter localement et modifier n'importe quel fichier du workspace (seule la
publication est bloquée), le réseau sortant n'est pas filtré, et les règles
projet — étant dans le workspace — sont supprimables.
