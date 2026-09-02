# Mode « amorcer »

Ni `package.json` ni `firebase.json` : le dépôt n'a rien qui dise « projet
Node ou Firebase ». Deux répertoires très différents tombent ici :

- **le cas nominal, un répertoire réellement vide**, destiné à Nx + Firebase.
  La stack est toujours la même : suis les sections 1 à 4 telles quelles.
- **un répertoire non vide**, mais sans manifeste Node ni Firebase reconnu —
  un dépôt Python ou Go bien rempli, par exemple. Vois la section 5 : elle
  remplace les sections 1 à 4 pour ce cas, ne s'y ajoute pas.

**Dans le cas nominal, l'ordre s'inverse : le container vient d'abord, le
projet naît dedans.** `nx create-workspace` et `firebase init` s'exécutent à
l'intérieur, avec la toolchain de l'image et le garde-fou déjà actif. Le poste
hôte n'a besoin ni de node ni de pnpm. `post-create.sh` le supporte tel quel,
puisqu'il n'appelle `mise run setup` que si la tâche existe.

## 1. Une seule question (cas nominal)

C'est le seul mode où tu interroges l'humain. Pose une question à choix
multiple : « Quels émulateurs Firebase ce projet utilisera-t-il ? », avec **Auth
et Firestore pré-cochés**. Ne propose que les émulateurs de la table de
`references/brancher.md` §1 — les autres (UI, Hosting, Functions) n'ont pas de
variable d'environnement, donc rien à écrire dans le fichier : les proposer
ferait choisir sur une question sans effet. Les ports, les variables et la règle
d'ajout à `containerEnv` sont ceux de cette même table — ne la redécris pas ici.

Si l'humain n'est pas joignable pour répondre, poursuis avec la sélection par
défaut (Auth, Firestore) et dis-le explicitement dans ce que tu écris : une
liste de variables incomplète se corrige en relançant le mode, un blocage sans
issue écrite laisse l'agent coincé sans recours.

Ne pose aucune autre question. L'identifiant de projet se déduit (§2).

## 2. L'identifiant de projet Firebase

`demo-<slug>`. Un identifiant préfixé `demo-` est traité par les émulateurs
comme purement local, sans backend réel derrière : le SDK ne peut pas se tromper
de cible, même si on lui fournissait des credentials. À remplacer le jour où le
projet Firebase existe — dis-le.

## 3. Écrire le fichier

Pars de `references/devcontainer.template.json`, commentaires compris, avec le
slug, `demo-<slug>` et les variables des émulateurs retenus.

N'écris pas de `mise.toml` : le workspace n'existe pas encore, et
`nx create-workspace` refuse un répertoire encombré. C'est le second passage qui
ajoutera la tâche `setup`.

## 4. Dire la suite, dans l'ordre

1. Ouvrir le dépôt dans le dev container — la première ouverture construit le
   container et lance le provisionnement.
2. Dedans, générer le projet : `pnpm create nx-workspace`, puis
   `firebase init` pour les émulateurs cochés.
3. Relancer `/devcontainer-init` : le dépôt a maintenant quelque chose à lire,
   et c'est le mode « mettre à jour » qui s'appliquera — il ajustera les
   variables d'émulateur sur ce qui est réellement configuré et ajoutera la
   tâche `setup`.

Ne génère pas l'application toi-même : `nx create-workspace` et `firebase init`
ont leurs propres générateurs, et ils sont à lancer dans le container, pas ici.

Dis-lui enfin que **le projet qui va naître dans ce container vivra dans un
volume Docker et pas sur son disque**, et qu'il ne survit pas à la recréation du
container. C'est plus aigu ici que dans les autres modes : le dépôt est vide,
donc il n'existe aucune copie ailleurs tant que rien n'a été poussé. Enchaîne sur
`references/github.md` — c'est ce qui rend le premier push possible. Le premier
push est donc à faire tôt, pas à la fin.

Dis-lui aussi que **le container ne construira pas d'image OCI** — la question
se pose tôt sur un projet qui naît, et plus tôt encore s'il vise un déploiement
conteneurisé. La raison est au README du dépôt des images, section « Ce que le
container ne sait pas faire » : ce n'est pas un réglage à ajuster, c'est une
propriété du dispositif.

## 5. Répertoire non vide, sans manifeste Node ni Firebase reconnu

Remplace les sections 1 à 4 pour ce cas : la question sur les émulateurs,
l'identifiant `demo-<slug>`, le report du `mise.toml` et les instructions
`nx create-workspace` supposent tous un projet Nx + Firebase à naître dans un
répertoire vide. Rien de tout cela ne tient ici — le répertoire est déjà
rempli, d'une autre stack.

- **Ne promets pas `nx create-workspace` ni `firebase init`.** Ces générateurs
  refusent un répertoire encombré, et celui-ci en est un. Il n'y a rien à
  générer, seulement à brancher tel quel — comme le ferait
  `references/brancher.md`, mais sans les manifestes Node/Firebase dont il
  dépend pour lire les émulateurs.
- **L'image se choisit sur la stack visée, pas par défaut.**
  `ghcr.io/charlouze/devcontainer-web:1` ne se justifie que pour une stack
  Nx/Angular/Firebase — improbable ici, puisque justement aucun manifeste ne
  l'atteste. Quand la stack visée n'est manifestement pas celle-là (un
  `pyproject.toml`, un `go.mod`, un `Cargo.toml`, …), prends
  `ghcr.io/charlouze/devcontainer-agent-base:1`. Dans ce cas, retire de
  `containerEnv` les quatre variables d'émulateur : ce sont des réglages d'une
  stack absente, la même règle qu'au mode « brancher » §2.
- **Dans le doute sur la stack visée, demande.** C'est le seul mode qui a le
  droit de poser une question (§1) ; sers-t'en ici plutôt que de supposer une
  stack sur la foi d'indices faibles.
- **Le reste suit `references/brancher.md`** : le nom du projet et le slug
  comme dans les règles communes de `SKILL.md`, et une tâche `setup` dans
  `mise.toml` (§3 de `brancher.md`, adaptée à la stack réellement présente —
  ce mode n'a pas de convention Python ou Go à imposer). Le report du
  `mise.toml` de la section 3 ci-dessus ne s'applique pas : ce répertoire a
  déjà un workspace, contrairement au cas nominal.

Termine comme le mode « brancher » §4 : liste de contrôle finale, montrer les
fichiers écrits, indiquer la suite (ouvrir dans le dev container, puis
`yolo`). Pas de relance de `/devcontainer-init` à annoncer ici : il n'y a pas
de second passage qui changerait quoi que ce soit.
