# Mode « amorcer »

Ni `package.json` ni `firebase.json` : il n'y a rien à lire. Mais il y a peu à
deviner — la stack est toujours la même et ses ports sont conventionnels.

**L'ordre s'inverse dans ce mode : le container vient d'abord, le projet naît
dedans.** `nx create-workspace` et `firebase init` s'exécutent à l'intérieur,
avec la toolchain de l'image et le garde-fou déjà actif. Le poste hôte n'a
besoin ni de node ni de pnpm. `post-create.sh` le supporte tel quel, puisqu'il
n'appelle `mise run setup` que si la tâche existe.

## 1. Une seule question

C'est le seul mode où tu interroges l'humain. Pose une question à choix
multiple : « Quels émulateurs Firebase ce projet utilisera-t-il ? », avec **UI,
Auth et Firestore pré-cochés**.

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

Chaque case cochée ajoute son port à `forwardPorts`, son libellé à
`portsAttributes` et sa variable à `containerEnv` — c'est cette dernière qui
empêche les SDK de viser autre chose que le local. Functions et Hosting n'ont
pas d'équivalent côté client : seul le port est à ouvrir.

Ne pose aucune autre question. Le port de serve est 4200, et l'identifiant de
projet se déduit (§2).

## 2. L'identifiant de projet Firebase

`demo-<slug>`. Un identifiant préfixé `demo-` est traité par les émulateurs
comme purement local, sans backend réel derrière : le SDK ne peut pas se tromper
de cible, même si on lui fournissait des credentials. À remplacer le jour où le
projet Firebase existe — dis-le.

## 3. Écrire le fichier

Pars de `references/devcontainer.template.json`, commentaires compris, avec le
slug, `demo-<slug>` et les ports retenus.

N'écris pas de `mise.toml` : le workspace n'existe pas encore, et
`nx create-workspace` refuse un répertoire encombré. C'est le second passage qui
ajoutera la tâche `setup`.

## 4. Dire la suite, dans l'ordre

1. Ouvrir le dépôt dans le dev container — la première ouverture construit le
   container et lance le provisionnement.
2. Dedans, générer le projet : `pnpm create nx-workspace`, puis
   `firebase init` pour les émulateurs cochés.
3. Relancer `/devcontainer-init` : le dépôt a maintenant quelque chose à lire,
   et c'est le mode « mettre à jour » qui s'appliquera — il ajustera les ports
   réellement configurés et ajoutera la tâche `setup`.

Ne génère pas l'application toi-même : `nx create-workspace` et `firebase init`
ont leurs propres générateurs, et ils sont à lancer dans le container, pas ici.
