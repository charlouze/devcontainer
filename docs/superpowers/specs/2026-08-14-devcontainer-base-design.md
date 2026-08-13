# Base de dev containers partagée pour agents autonomes

Date : 2026-08-14
État : design validé, prêt pour la planification d'implémentation

## 1. Objectif

Factoriser dans une base réutilisable le dev container aujourd'hui propre à
Compte-de-Famille, afin de lancer Claude Code en mode YOLO
(`--dangerously-skip-permissions`) sur n'importe lequel des projets personnels,
avec les mêmes garanties de confinement et sans recopier la configuration d'un
dépôt à l'autre.

Le container **est** la barrière de sécurité : l'agent y a carte blanche, et ce
qu'il ne doit pas pouvoir faire doit lui être rendu impossible, pas déconseillé.

## 2. Périmètre

Dans le périmètre :

- une image `agent-base` portant le durcissement, l'agent et le provisionnement
  générique ;
- une image `web` pour le modèle Nx + Angular + pnpm + Firebase ;
- un garde-fou révisé, extensible par projet de façon additive ;
- la publication des images sur GHCR via GitHub Actions ;
- un plugin Claude Code d'onboarding (brancher, migrer, amorcer un dépôt) ;
- un smoke test exécuté en CI ;
- la migration de Compte-de-Famille sur cette base.

Hors périmètre :

- **Unity.** `agent-base` est conçu pour accueillir une seconde image plus tard,
  mais rien n'est fait dans ce sens maintenant.
- **arm64.** amd64 uniquement ; le multi-arch est possible sans changement de
  structure le jour où c'est utile.
- **La génération d'applications.** `nx create-workspace` et `firebase init` ont
  leurs propres générateurs. Le plugin d'onboarding s'occupe du container, rien
  d'autre.

## 3. Décisions structurantes

| Décision | Retenu | Raison |
|---|---|---|
| Distribution | Image publiée sur GHCR | Rebuild central, projets légers, mise à jour par bump de tag |
| Découpage | `agent-base` + `web` | Unity héritera du premier sans le second |
| Garde-fou | Socle en image + extension projet additive | Le socle est incontournable ; le projet ne peut qu'ajouter |
| Toolchain | mise en user-level | Chaque projet garde l'autonomie de son `mise.toml` |
| Provisionnement | `mise run setup` | Le contrat base ↔ projet est `mise.toml`, pas un script shell |
| Volumes | Partage sélectif | Login et store mutualisés, backend IDE isolé |
| Onboarding | Plugin Claude Code | Doit lire le dépôt existant, ce qu'un template ne sait pas faire |

## 4. Structure du dépôt

```
charlouze/devcontainer
├─ images/
│  ├─ agent-base/
│  │  ├─ Dockerfile
│  │  ├─ guard/
│  │  │  ├─ agent-guard.cjs        # socle + chargement des règles projet
│  │  │  ├─ run                    # wrapper d'invocation
│  │  │  └─ managed-settings.json
│  │  ├─ etc/
│  │  │  ├─ history.sh
│  │  │  └─ plugins.d/00-base.txt
│  │  └─ post-create.sh
│  └─ web/
│     ├─ Dockerfile
│     └─ etc/plugins.d/10-web.txt
├─ plugin/                          # plugin Claude Code d'onboarding
│  ├─ .claude-plugin/
│  ├─ commands/devcontainer-init.md
│  └─ skills/onboard-devcontainer/SKILL.md
├─ .claude-plugin/marketplace.json  # le dépôt est sa propre marketplace
├─ templates/web/devcontainer.json  # fichier de référence, copié par le plugin
├─ tests/smoke.sh
├─ docs/
└─ .github/workflows/publish.yml
```

Images publiées :

- `ghcr.io/charlouze/devcontainer-agent-base`
- `ghcr.io/charlouze/devcontainer-web`

Tags : `1` (flottant sur la majeure), `1.x.y`, et le sha du commit. Dépôt public,
donc aucun jeton d'accès nécessaire côté poste de dev.

## 5. Image `agent-base`

Base `mcr.microsoft.com/devcontainers/base:bookworm` — Debian glibc, requis par
le backend IDE JetBrains, qui ne fonctionne pas sur musl.

Contenu :

- utilisateur `vscode` renommé `dev` (login, home, groupe, `sudoers.d`) ;
- paquets système : `build-essential`, `ca-certificates`, `curl`, `git`, `gnupg`,
  `jq`, `less`, `procps`, `ripgrep`, `unzip`, `xz-utils` ;
- `nodejs` du dépôt Debian, qui sert **uniquement** d'interprète au garde-fou ;
- `mise`, installé pour l'utilisateur `dev` ;
- Claude Code via l'installeur natif (`~/.local/bin`, se met à jour sans root) ;
- alias `yolo` = `claude --dangerously-skip-permissions` ;
- le garde-fou, root-only ;
- `/usr/local/share/devcontainer/post-create.sh` ;
- `/etc/devcontainer/history.sh` et `/etc/devcontainer/plugins.d/00-base.txt` ;
- les points de montage des volumes, créés avec le bon propriétaire pour que
  Docker initialise les volumes vides sous `dev` et non sous root.

### 5.1 Chargement de l'environnement shell

Les snippets d'environnement (`mise`, historique) sont écrits dans
`/etc/devcontainer/` et sourcés depuis **deux** endroits, chacun protégé par une
sentinelle contre le double chargement :

- `/etc/profile.d/` — les terminaux de l'IDE sont des shells de login ;
- `/etc/bash.bashrc` — un `docker exec bash` ne l'est pas et ne lit que celui-ci.

`/etc/profile` réécrit `PATH` de zéro et efface donc ce qui vient des directives
`ENV` du Dockerfile : les shims mise doivent être réinjectés après coup, sans
quoi `node` est introuvable dans le terminal alors qu'il fonctionne dans les
scripts.

## 6. Image `web`

`FROM` `agent-base`, plus :

- `mise use --global node@22 pnpm@latest java@25` sous l'utilisateur `dev` —
  préinstallation à titre de **cache chaud** uniquement, pas de contrainte : un
  projet qui demande autre chose l'installera lui-même ;
- `playwright install-deps chromium webkit` (dépendances système des
  navigateurs ; les navigateurs eux-mêmes vont dans un volume) ;
- `/etc/devcontainer/plugins.d/10-web.txt`.

Java sert aux émulateurs Firestore, Realtime Database et Pub/Sub. Il est
préinstallé pour que le premier `mise run emulators` ne parte pas en
téléchargement de 300 Mo.

## 7. Le garde-fou

`--dangerously-skip-permissions` saute les demandes de confirmation, pas les
hooks : un `PreToolUse` qui sort en code 2 bloque quand même l'appel d'outil.
C'est donc là que vivent les interdits qui doivent tenir quand l'agent a carte
blanche.

### 7.1 Ancrage

Trois propriétés le rendent incontournable. Chacune répond à un contournement
identifié.

**Interprète dédié.** Le hook s'exécute avec `/usr/bin/nodejs` (paquet Debian,
root-only), et non plus avec le `node` de mise. C'est ce qui permet à l'arbre
mise de redescendre en user-level : l'agent peut installer les outils qu'il veut
sans jamais toucher l'interpréteur du garde-fou.

**Activation par marqueur, pas par variable d'environnement.** L'implémentation
actuelle teste `process.env.CDF_SANDBOX !== '1'`. Or l'agent contrôle
l'environnement des processus qu'il lance : `env -u CDF_SANDBOX claude
--dangerously-skip-permissions` ouvre une session sans garde-fou. Le test devient
l'existence de `/etc/claude-guard/enabled` (root, 0444), qui n'est pas
falsifiable. Le fichier source reste inerte hors container, puisque le marqueur
n'existe que dans l'image.

**Wrapper anti-injection.** Même raisonnement pour `NODE_OPTIONS=--require
/tmp/neutralise.js`, préchargé avant le script et capable de le neutraliser. Le
hook passe par `/usr/local/lib/claude-guard/run` (root, 0555) :

```sh
#!/bin/sh
exec env -u NODE_OPTIONS -u NODE_PATH /usr/bin/nodejs \
     /usr/local/lib/claude-guard/agent-guard.cjs "$@"
```

Déploiement, en dernière couche du Dockerfile pour qu'une modification du
garde-fou ne réinvalide ni l'apt ni les navigateurs Playwright :

| Chemin | Propriétaire | Mode |
|---|---|---|
| `/usr/local/lib/claude-guard/` | root:root | 0755 |
| `/usr/local/lib/claude-guard/run` | root:root | 0555 |
| `/usr/local/lib/claude-guard/agent-guard.cjs` | root:root | 0555 |
| `/etc/claude-guard/` | root:root | 0755 |
| `/etc/claude-guard/enabled` | root:root | 0444 |
| `/etc/claude-code/` | root:root | 0755 |
| `/etc/claude-code/managed-settings.json` | root:root | 0444 |

Les répertoires sont créés explicitement : laissé à `COPY --chmod`, BuildKit
applique le mode du fichier au parent qu'il crée, et un répertoire en 0444 n'est
pas traversable — les managed settings ne seraient jamais chargés, et le
garde-fou tomberait en panne silencieuse.

Les managed settings sont de priorité maximale et non surchargeables par les
settings utilisateur ou projet. C'est ce qui distingue ce garde-fou d'un hook
posé dans le workspace, que l'agent pourrait éditer.

### 7.2 Socle de règles

Commandes bash bloquées :

- `git push`, `git remote set-url|add|rename`, `git config --global|--system` ;
- `firebase deploy|hosting:|functions:|firestore:delete|target|login|apps:|projects:` ;
- `gcloud`, `gsutil`, `bq` ;
- `npm|pnpm|yarn publish` ;
- `gh secret|release|workflow|auth token|repo delete|repo edit` ;
- `curl … | sh` (télécharger puis exécuter à la volée).

Chemins interdits en lecture comme en écriture, quel que soit l'outil :

- `.env` et variantes ;
- `.ssh/`, `id_rsa|ecdsa|ed25519`, `*.pem`, `*.credentials.json` ;
- clés de compte de service (`serviceaccount*.json`, `*-firebase-adminsdk-*.json`) ;
- `~/.history/bash_history` — un historique de shell contient régulièrement des
  jetons collés à la main.

Chaque blocage sort en code 2 avec sa raison sur stderr, renvoyée à l'agent.

Pas de règle sur le jeton d'authentification de l'agent : elle serait
décorative. Ce que le garde-fou ne protège pas doit être documenté comme tel.

### 7.3 Extension par projet

Le garde-fou lit `${CLAUDE_PROJECT_DIR}/.devcontainer/guard-rules.json` s'il
existe :

```json
{
  "bash":  [{ "pattern": "\\bstripe\\s+", "flags": "i", "reason": "…" }],
  "paths": [{ "pattern": "fixtures/prod-.*\\.json$", "reason": "…" }]
}
```

Ce fichier est dans le workspace, donc éditable par l'agent. La garantie tient
par construction et non par permission : **le socle est évalué en premier**. Un
blocage du socle sort en code 2 avant que le fichier projet soit seulement lu.
Conséquences :

- supprimer ou vider le fichier ne lève aucun interdit ;
- y écrire une regex à backtracking catastrophique pour faire expirer le hook —
  un timeout étant traité comme non bloquant — ne peut neutraliser que les règles
  projet, jamais le socle.

Tolérance aux erreurs : fichier absent, illisible, supérieur à 64 Ko, JSON
invalide, plus de 100 règles, ou regex non compilable → avertissement sur stderr,
on continue avec le socle. Ni fail-open silencieux, ni blocage total sur une
erreur de configuration.

## 8. Toolchain

`mise` en user-level (`~/.local/share/mise`), inscriptible par `dev`.
`mise install` fonctionne à chaud : chaque projet applique son `mise.toml` sans
rebuild ni alignement sur l'image.

Ce que l'image apporte n'est plus une contrainte mais une accélération : node,
pnpm et java y sont déjà, donc `mise install` est instantané dans le cas courant.

Les outils installés à chaud vivent dans `~/.local/share/mise`, qui n'est pas un
volume : un rebuild les perd. Ce n'est pas un problème, parce que le post-create
rejoue `mise install` et que le cache de téléchargement de mise, lui, est dans
`~/.cache/mise`, donc sur le volume par projet. Un rebuild réinstalle sans
retélécharger. Le cache n'est volontairement pas redirigé vers un chemin système :
il y resterait root-only et mise avertirait à chaque commande.

Bénéfice de bord : le runtime des Cloud Functions suit le champ `engines` de leur
`package.json`, qui ne correspond pas nécessairement au node de l'application.
Cette version s'installe désormais sans toucher à l'image.

## 9. Provisionnement

`/usr/local/share/devcontainer/post-create.sh`, root 0555, idempotent, rejoué à
chaque rebuild. Séquence :

1. **Identité.** Affiche l'utilisateur ; avertit bruyamment si les lifecycle
   scripts tournent en root (le durcissement repose sur le fait que l'agent est
   `dev`) ou si le workspace n'est pas inscriptible.
2. **mise.** `mise trust --yes` puis `mise install --yes`.
3. **Store pnpm.** Voir §10.
4. **Réglages Claude Code.** `skipDangerousModePermissionPrompt = true` — en
   sandbox, l'avertissement n'apporte rien, le container est la barrière.
5. **Plugins.** Voir §9.1.
6. **Git.** `git config --global --add safe.directory "$PWD"`.
7. **Projet.** `mise run setup` si la tâche existe. Un dépôt vide n'en a pas
   encore : c'est un cas normal, pas une erreur.
8. **Bannière.** Rappelle `yolo`, liste les garde-fous actifs, et indique si des
   règles projet ont été chargées — sans quoi un `guard-rules.json` mal formé
   passerait inaperçu.

### 9.1 Plugins Claude Code

La liste est une donnée, répartie par couche d'image, une ligne valant
`<marketplace> <plugin>` :

```
# /etc/devcontainer/plugins.d/00-base.txt   (posé par agent-base)
anthropics/claude-plugins-official  superpowers
charlouze/devcontainer              devcontainer

# /etc/devcontainer/plugins.d/10-web.txt    (posé par web)
pbakaus/impeccable                  impeccable
```

Le post-create itère sur les fichiers dans l'ordre : `claude plugin marketplace
add`, puis `claude plugin install <plugin>@<marketplace>`, les deux tolérants au
déjà-installé. Il ne juge que l'état final via `claude plugin details`, qui sort
en 1 tant que le plugin n'est pas installé — être présent dans une marketplace ne
suffit pas. Un échec produit un avertissement nommant la commande à rejouer, sans
faire tomber le reste du provisionnement.

La marketplace officielle n'est enregistrée d'office qu'au premier lancement
*interactif* de `claude` ; le post-create ne l'étant pas, l'ajout doit être
explicite.

Le découpage par couche est volontaire : Superpowers est générique, Impeccable
est un vocabulaire de design d'interface et n'a de sens que sur le modèle web.
`~/.claude` étant un volume partagé entre projets, les plugins le sont aussi : la
couche d'image détermine ce qui est *installé*, pas ce qui est *visible*.

Sur Impeccable, le README amont recommande `npx impeccable install` plutôt que la
voie plugin. Vérifications faites, ce n'est pas un défaut du plugin : le
répertoire `plugin/` contient bien `agents/`, `hooks/` et `skills/`, et il est
régénéré par une Action CI en même temps que la source. La recommandation
s'adresse à une audience multi-harness, dont nous ne sommes pas. Ici la voie
plugin est supérieure : l'installeur CLI dépose des fichiers *dans le dépôt*, ce
qui pollue les diffs d'un agent autorisé à commiter et impose une installation
par projet, là où le plugin vit dans `~/.claude`, partagé et hors des dépôts.

### 9.2 Contrat côté projet

Le projet décrit son provisionnement dans son `mise.toml`, au même endroit que
ses tâches de dev, versionné et rejouable à la main hors container :

```toml
[tasks.setup]
description = "Provisionnement du dev container"
run = """
mise run install
pnpm exec playwright install chromium webkit
"""
```

## 10. Store pnpm

Réglages écrits par le post-create dans `~/.config/pnpm/config.yaml` :

```yaml
storeDir: /home/dev/.cache/pnpm-store
packageImportMethod: copy
```

Le raisonnement doit voyager avec le réglage, car le symptôme ne mène pas à la
cause. pnpm veut son store sur le même système de fichiers que le projet, pour
créer des liens durs vers `node_modules` au lieu de copier. Or le workspace et le
store sont deux montages distincts : le lien dur est impossible. Sans `storeDir`
explicite, pnpm ignore le volume et se fabrique un store **dans le projet** —
environ 900 Mo et 51 000 fichiers. IntelliJ l'embarque alors dans son scan
« detecting project structure », qu'il effectue fichier par fichier via IJent,
mesuré à 1 Go poussé sur le socket gRPC. Le symptôme observé n'est pas « pnpm est
lent » mais « l'IDE ne finit jamais de démarrer ».

`packageImportMethod: copy` est écrit explicitement plutôt que laissé au repli
automatique de pnpm : une image partagée qui suit `pnpm@latest` verra passer des
versions majeures, et un comportement de repli n'est pas un contrat.

Le réglage est délibérément global et non dans `pnpm-workspace.yaml` : ce dernier
est versionné et partagé avec la CI, où `/home/dev/.cache` n'existe pas. pnpm 11
ne lit ni `.npmrc` ni `~/.config/pnpm/rc` pour ce réglage, uniquement
`config.yaml`.

Coût assumé : environ +8 s à l'installation et ~1 Go de `node_modules` copié par
projet, contre un store unique partagé entre tous les dépôts et hors de l'arbre
indexé par l'IDE.

Ce comportement n'est pas tenu pour acquis : le smoke test l'arbitre (§14).

## 11. Historique bash

Volume dédié par projet monté sur `/home/dev/.history`. Pas un coin de
`~/.cache` : un cache est légitimement jetable, et supprimer un volume de cache
pour récupérer de la place ne doit pas coûter l'historique.

Par projet et non partagé, contrairement à `~/.claude` : un `Ctrl+R` n'a
d'intérêt que s'il retombe sur les commandes de *ce* dépôt, et deux containers
ouverts simultanément s'écriraient dessus.

`/etc/devcontainer/history.sh` :

```sh
export HISTFILE=/home/dev/.history/bash_history
export HISTSIZE=100000 HISTFILESIZE=200000
export HISTCONTROL=ignoreboth
shopt -s histappend
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
```

`history -a` après chaque commande, et non à la sortie du shell : un rebuild tue
les processus sans passer par la terminaison normale de bash — c'est précisément
le cas à couvrir, et celui où l'écriture différée perd tout. `histappend`
empêche qu'un shell qui se ferme tronque ce que les autres ont écrit.
`ignoreboth` plutôt que `erasedups` : la déduplication rétroactive réécrit la
liste en mémoire alors que `history -a` ne pousse que les nouvelles lignes, et
les deux ensemble perdent des entrées.

L'outil Bash de l'agent tourne dans un shell non interactif et n'écrit donc pas
dans `HISTFILE` : l'historique reste celui de l'humain.

## 12. Volumes

| Volume | Cible | Portée | Contenu |
|---|---|---|---|
| `agent-claude` | `/home/dev/.claude` | partagé | login, sessions, plugins |
| `agent-pnpm-store` | `/home/dev/.cache/pnpm-store` | partagé | store pnpm |
| `agent-playwright` | `/home/dev/.cache/ms-playwright` | partagé | navigateurs |
| `<projet>-cache` | `/home/dev/.cache` | par projet | backend JetBrains, divers |
| `<projet>-history` | `/home/dev/.history` | par projet | historique bash |

Sont partagés `~/.claude` — login une fois, plugins installés une fois — et les
caches content-addressed, où le partage est sûr par construction. Reste par
projet le backend JetBrains, que deux containers concurrents ne doivent pas se
disputer.

Les montages sont imbriqués (`~/.cache`, puis `~/.cache/pnpm-store`). Cela repose
sur l'ordonnancement des montages par profondeur de chemin — parent d'abord —
qui est vérifié par le smoke test plutôt que supposé (§15).

## 13. Contrat côté projet

Le durcissement runtime reste explicite dans le `devcontainer.json` du projet.
**Rien de critique ne passe par le label `devcontainer.metadata` de l'image** :
`runArgs` et `capDrop` n'en font pas partie, et le support des labels d'image par
le plugin devcontainer de JetBrains est incertain. Faire dépendre
`postCreateCommand` d'un label ignoré donnerait une panne silencieuse de tout le
provisionnement.

```json
{
  "name": "Compte-de-Famille (agent sandbox)",
  "image": "ghcr.io/charlouze/devcontainer-web:1",

  "containerUser": "root",
  "remoteUser": "dev",

  "containerEnv": {
    "FIRESTORE_EMULATOR_HOST": "127.0.0.1:8080",
    "FIREBASE_AUTH_EMULATOR_HOST": "127.0.0.1:9099",
    "GCLOUD_PROJECT": "compte-de-famille-dev",
    "GOOGLE_CLOUD_PROJECT": "compte-de-famille-dev"
  },

  "mounts": [
    "source=agent-claude,target=/home/dev/.claude,type=volume",
    "source=cdf-cache,target=/home/dev/.cache,type=volume",
    "source=agent-pnpm-store,target=/home/dev/.cache/pnpm-store,type=volume",
    "source=agent-playwright,target=/home/dev/.cache/ms-playwright,type=volume",
    "source=cdf-history,target=/home/dev/.history,type=volume"
  ],

  "runArgs": [
    "--security-opt", "no-new-privileges",
    "--cap-drop", "ALL",
    "--cap-add", "CHOWN", "--cap-add", "FOWNER", "--cap-add", "DAC_OVERRIDE",
    "--cap-add", "SETUID", "--cap-add", "SETGID"
  ],

  "forwardPorts": [4200, 4000, 8080, 9099],
  "portsAttributes": {
    "4200": { "label": "App Angular" },
    "4000": { "label": "Firebase Emulator UI" },
    "8080": { "label": "Firestore emulator" },
    "9099": { "label": "Auth emulator" }
  },

  "postCreateCommand": "/usr/local/share/devcontainer/post-create.sh",

  "customizations": {
    "jetbrains": {
      "backend": "IntelliJ",
      "plugins": ["com.github.l34130.mise"]
    }
  }
}
```

Notes sur ce fichier, à conserver dans le template :

- `containerUser: root` / `remoteUser: dev` — le clone-from-VCS est fait par un
  container helper tournant en root ; l'arbre appartient à root et JetBrains doit
  le rendre à `dev` avant les lifecycle scripts, ce qui exige root et `CAP_CHOWN`.
  L'IDE, les terminaux et les lifecycle scripts tournent sous `remoteUser`.
- Les capabilities conservées ne servent qu'à cette mise en place. Un uid
  non-root a de toute façon un jeu de capabilities effectif vide, et
  `no-new-privileges` lui interdit de passer root.
- `no-new-privileges` neutralise `sudo` : aucun outil ne s'ajoute à chaud côté
  système. Ni `SYS_ADMIN` ni droit de montage, donc pas de chemin d'évasion connu.
- Rien d'autre dans `runArgs` : le parser d'IntelliJ ne connaît qu'un
  sous-ensemble des options `docker run` et échoue sur les autres
  (`ParseException: Unrecognized argument`). Les plafonds CPU/RAM se règlent dans
  `%UserProfile%\.wslconfig`.
- Aucun credential cloud n'entre dans le container. Combiné aux variables
  d'émulateur, le SDK Admin ne peut atteindre que l'émulateur local : sans
  Application Default Credentials, il échoue au lieu d'écrire dans le vrai projet.

## 14. Onboarding : plugin `devcontainer`

Le dépôt est sa propre marketplace Claude Code et expose un plugin contenant un
skill et une commande `/devcontainer-init`. Installé une fois sur le poste, il
est disponible dans tous les dépôts ; il est aussi listé dans `plugins.d` pour
être présent dans les containers.

Deux raisons de le loger ici plutôt qu'ailleurs : il doit être disponible
**avant** que le container existe, donc côté machine et pas dans l'image ; et
être versionné avec les images garantit qu'il ne pose jamais un tag inexistant.

Le mécanisme standard de templates Dev Container a été écarté : il sait déposer
des fichiers dans un dépôt vide, mais ne sait ni lire un projet existant ni
migrer une configuration déjà en place — les deux cas les plus fréquents ici.

Un seul point d'entrée, trois modes déduits de ce que le dépôt contient.

### 14.1 Brancher

Le dépôt a du code mais pas de `.devcontainer`. Le skill lit :

- `firebase.json` → section `emulators` si présente (source d'autorité, y compris
  pour les ports déplacés) ; sinon les clés produits de premier niveau
  (`firestore`, `functions`, `hosting`, `storage`, `database`), chaque produit
  prenant son port par défaut ; et l'identifiant de projet ;
- `.firebaserc` → identifiant de projet ;
- `angular.json` / `nx.json` → port de serve ;
- `package.json` → version de Playwright.

Il écrit `.devcontainer/devcontainer.json` depuis le template, avec les volumes
préfixés par un slug dérivé du nom du dépôt, et ajoute `[tasks.setup]` au
`mise.toml` si la tâche est absente.

### 14.2 Migrer

Le dépôt a déjà un `.devcontainer` — le cas de Compte-de-Famille. Le skill en
extrait ce qui appartient réellement au projet (ports, variables d'émulateur,
règles de garde-fou spécifiques), produit la version courte, et signale les
fichiers devenus inutiles parce que l'image les fournit : `Dockerfile`,
`post-create.sh`, `agent-guard.cjs`, `managed-settings.json`. Rien n'est supprimé
sans que le diff soit montré.

### 14.3 Amorcer

Dépôt vide : ni `package.json`, ni `firebase.json`. Il n'y a rien à lire, mais
peu à deviner — la stack est toujours la même et ses ports sont conventionnels.
Le skill demande **uniquement dans ce mode** quels émulateurs seront utilisés,
en sélection multiple, avec UI, Auth et Firestore pré-cochés :

| Émulateur | Port | Variable d'environnement |
|---|---|---|
| UI | 4000 | — |
| Hosting | 5000 | — |
| Functions | 5001 | — |
| Firestore | 8080 | `FIRESTORE_EMULATOR_HOST` |
| Pub/Sub | 8085 | `PUBSUB_EMULATOR_HOST` |
| Realtime Database | 9000 | `FIREBASE_DATABASE_EMULATOR_HOST` |
| Auth | 9099 | `FIREBASE_AUTH_EMULATOR_HOST` |
| Storage | 9199 | `FIREBASE_STORAGE_EMULATOR_HOST` |

Chaque case cochée ajoute son port aux `forwardPorts`, son libellé aux
`portsAttributes` et sa variable au `containerEnv` — c'est cette dernière qui
empêche les SDK de viser autre chose que le local. Functions et Hosting n'ont pas
d'équivalent côté client : l'émulateur injecte lui-même l'environnement dans le
runtime des fonctions, seul le port est à ouvrir.

L'identifiant de projet Firebase, seule vraie inconnue, prend la valeur
`demo-<slug>` : un identifiant préfixé `demo-` est traité par les émulateurs
comme purement local, sans backend réel derrière, donc le SDK ne peut pas se
tromper de cible même si on lui fournissait des credentials. À remplacer le jour
où le projet Firebase existe.

**L'ordre s'inverse dans ce mode : le container vient d'abord, le projet naît
dedans.** `nx create-workspace` et `firebase init` sont exécutés à l'intérieur,
avec la toolchain de l'image et le garde-fou déjà actif. Le poste hôte n'a besoin
ni de node ni de pnpm. Le post-create le supporte sans rien de plus, puisqu'il
n'appelle `mise run setup` que si la tâche existe.

Une fois le workspace généré, relancer `/devcontainer-init` : le dépôt a
désormais quelque chose à lire, et c'est le mode mise à jour qui s'applique.

### 14.4 Mettre à jour

Relancé sur un dépôt déjà branché, le skill bump le tag d'image et signale les
écarts entre le fichier du dépôt et le template courant. C'est ce cas qui
justifie l'outil davantage que le premier branchement : quand la base passe en
`2`, il faut repasser sur chaque dépôt.

Le skill ne génère pas d'application, et n'invente aucune étape d'installation.
En particulier, il n'ajoute rien pour Cloud Functions au-delà du port : dans un
dépôt Nx, les fonctions sont une app du workspace, couverte par le `pnpm install`
racine. L'enchaînement build → émulateurs, lui, relève du `mise.toml` du projet,
puisque la clé `source` de `firebase.json` pointe généralement vers la sortie de
build.

## 15. Publication

GitHub Actions, sur push de tag :

- build des deux images avec `docker/build-push-action`, `agent-base` d'abord ;
- push vers GHCR sur les tags `1`, `1.x.y`, sha ;
- exécution du smoke test sur l'image construite **avant** publication du tag
  flottant `1`, pour qu'un échec n'atteigne jamais les projets.

## 16. Tests

`tests/smoke.sh`, rejoué en CI après le build. Ce qui est protégé ici n'est
vérifiable que par exécution.

Durcissement :

- `id -un` vaut `dev` ;
- `/usr/local/lib/claude-guard/*`, `/etc/claude-guard/enabled` et
  `/etc/claude-code/managed-settings.json` ne sont modifiables ni supprimables
  par `dev` ;
- `sudo` échoue.

Garde-fou :

- un payload `{"tool_name":"Bash","tool_input":{"command":"git push"}}` sort en 2 ;
- il sort toujours en 2 avec toute variable d'environnement retirée, et avec
  `NODE_OPTIONS` pointant un préchargement hostile ;
- un `guard-rules.json` valide ajoute bien un interdit ;
- supprimer, vider, corrompre ce fichier, ou y placer une regex à backtracking
  catastrophique, ne lève aucun interdit du socle ;
- une lecture de `.env` et une lecture de `~/.history/bash_history` sortent en 2.

Toolchain et provisionnement :

- `mise install node@24` réussit sous `dev` ;
- les plugins listés dans `plugins.d` répondent à `claude plugin details` ;
- `mise run setup` absent ne fait pas échouer le post-create.

pnpm :

- après `pnpm install` dans un workspace jetable, `pnpm store path` tombe dans le
  volume, et **aucun** répertoire de store n'est apparu sous le workspace ;
- les montages imbriqués se sont établis dans le bon ordre.

Historique :

- une commande écrite dans l'historique est toujours présente après recréation du
  container sur le même volume.

## 17. Migration de Compte-de-Famille

Dernière étape, via le mode « migrer » du plugin :

- `.devcontainer/` réduit au seul `devcontainer.json` ;
- `Dockerfile`, `post-create.sh`, `agent-guard.cjs`, `managed-settings.json`
  supprimés ;
- `[tasks.setup]` ajouté au `mise.toml` ;
- `README.md` du `.devcontainer` réduit à ce qui est propre au projet, le reste
  renvoyant à la documentation du dépôt de base.

Aucun changement fonctionnel attendu côté développeur : mêmes ports, mêmes
tâches, mêmes garde-fous.

## 18. Points à vérifier à l'implémentation

Chacun est une hypothèse de design, à confirmer avant de s'appuyer dessus :

1. Ordonnancement des montages imbriqués par Docker (parent avant enfant).
   Couvert par le smoke test ; si l'hypothèse tombe, le store et les navigateurs
   déménagent hors de `~/.cache`.
2. Propriétés réellement acceptées dans le label `devcontainer.metadata`, et
   comportement du plugin JetBrains vis-à-vis de ce label. Le design n'en dépend
   pas — c'est précisément pourquoi il n'en dépend pas.
3. Version de `nodejs` fournie par bookworm, et sa capacité à exécuter le
   garde-fou. À défaut, copier un binaire node figé en root-only.
4. Que `~/.config/pnpm/config.yaml` reste le fichier lu pour `storeDir` sur la
   version de pnpm embarquée. Couvert par le smoke test.
5. Que `claude plugin install` fonctionne bien en non-interactif pour Impeccable
   comme pour Superpowers.

## 19. Ce que le garde-fou ne protège pas

À documenter dans le README du dépôt, comme dans l'existant :

- le jeton d'authentification de l'agent est lisible depuis la session ;
- l'agent peut commiter localement et modifier n'importe quel fichier du
  workspace ; seule la publication est bloquée ;
- l'accès réseau sortant n'est pas filtré ;
- les règles projet, étant dans le workspace, sont supprimables — elles ne
  peuvent qu'ajouter au socle, jamais s'y substituer.
