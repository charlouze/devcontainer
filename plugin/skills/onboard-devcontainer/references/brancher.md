# Mode « brancher »

Le dépôt a du code et pas de `.devcontainer/`. Tout ce qu'il faut savoir est
déjà dans le dépôt : lis-le, n'interroge pas l'humain.

## 1. Lire le dépôt

**`firebase.json`** — si une section `emulators` existe, **elle fait autorité**,
y compris pour un port déplacé, et ce indépendamment de ce qui figure par
ailleurs à la racine du fichier. Chaque émulateur qui y figure est à ouvrir ;
s'il n'y précise pas de `port`, prends le port par défaut de la table
ci-dessous. Une clé produit de premier niveau (`hosting`, `firestore`,
`functions`, …) absente de `emulators` ne démarre pas : c'est de la
configuration de déploiement, pas un émulateur à ouvrir — ne la complète pas
avec un port par défaut au prétexte qu'elle existe ailleurs dans le fichier.

Seulement si la section `emulators` est absente du fichier tout entier, prends
les clés produits de premier niveau (`firestore`, `functions`, `hosting`,
`storage`, `database`) et donne à chacune son port par défaut. L'émulateur UI
n'a pas de clé produit : ouvre son port dès qu'il y a des émulateurs, dans les
deux cas.

| Émulateur | Port par défaut | Variable d'environnement |
|---|---|---|
| UI | 4000 | — |
| Hosting | 5000 | — |
| Functions | 5001 | — |
| Firestore | 8080 | `FIRESTORE_EMULATOR_HOST` |
| Pub/Sub | 8085 | `PUBSUB_EMULATOR_HOST` |
| Realtime Database | 9000 | `FIREBASE_DATABASE_EMULATOR_HOST` |
| Auth | 9099 | `FIREBASE_AUTH_EMULATOR_HOST` |
| Storage | 9199 | `FIREBASE_STORAGE_EMULATOR_HOST` |

La variable vaut `127.0.0.1:<port>`. C'est elle qui empêche les SDK de viser
autre chose que le local. Functions et Hosting n'ont pas d'équivalent côté
client — l'émulateur injecte lui-même l'environnement dans le runtime des
fonctions, seul le port est à ouvrir.

**`.firebaserc`** — `projects.default` donne l'identifiant de projet, qui
alimente `GCLOUD_PROJECT` et `GOOGLE_CLOUD_PROJECT`. Absent, cherche-le dans
`firebase.json` ; toujours absent, prends `demo-<slug>` et dis-le.

**Le port de serve** — le chemin de clé dépend du format, et les deux peuvent
coexister le temps d'une migration Angular→Nx :

- `project.json` (Nx moderne) — `targets.serve.options.port` ;
- `angular.json` (Angular CLI, ou un Nx qui garde encore ce format) —
  `projects.<app>.architect.serve.options.port`.

`nx.json` est la config du workspace (défauts de targets, task runner) : il ne
porte normalement pas le port de serve d'un projet précis, ne le lis pas pour
cette valeur. Si `project.json` et `angular.json` coexistent pour le même
projet, `project.json` prime — c'est la source que Nx résout en premier une
fois la migration commencée. À défaut de tout, 4200.

**`package.json`** — la présence de `@playwright/test` décide de la ligne
Playwright de la tâche `setup`, et de rien d'autre.

## 2. Écrire `.devcontainer/devcontainer.json`

Pars de `references/devcontainer.template.json`, garde ses commentaires, et
remplace :

- `<Nom du projet>` — le nom du projet, comme défini dans les règles communes
  de `SKILL.md` ;
- `<projet-firebase>` — l'identifiant trouvé plus haut ;
- `<slug>` — le slug, dans les deux sources de volumes concernées.

Puis ajuste `containerEnv`, `forwardPorts` et `portsAttributes` d'après les
émulateurs détectés : une variable par émulateur qui en a une, un port et un
libellé par émulateur ouvert, plus le port de serve.

Si le dépôt n'a pas de Firebase du tout, retire les variables d'émulateur et
leurs ports : ne laisse pas des réglages qui décrivent une stack absente.

## 3. Ajouter la tâche `setup` au `mise.toml`

C'est le contrat entre l'image et le projet : `post-create.sh` lance
`mise run setup` si la tâche existe. N'y mets que le provisionnement, pas les
tâches de dev.

Si le dépôt a déjà une tâche d'installation, appelle-la plutôt que de la
dupliquer :

```toml
[tasks.setup]
description = "Provisionnement du dev container"
run = """
mise run install
pnpm exec playwright install chromium webkit
"""
```

Sinon, `pnpm install --frozen-lockfile` à la place de `mise run install`. La
ligne Playwright ne se met que si `@playwright/test` est une dépendance : les
navigateurs vont dans un volume partagé, leurs dépendances système sont déjà
dans l'image.

Si le dépôt n'a pas de `mise.toml`, crée-le avec la seule section `[tasks.setup]`
— les versions d'outils sont l'affaire du projet, pas la tienne.

## 4. Terminer

Repasse la liste de contrôle finale de `SKILL.md`, montre les deux fichiers
écrits, et indique la suite : ouvrir le dépôt dans le dev container, puis `yolo`.
