# Persistance de l'état de Claude Code entre rebuilds

Date : 2026-08-14
État : design validé, prêt pour la planification d'implémentation

## 1. Objectif

Faire survivre l'état de Claude Code à la recréation d'un container. Aujourd'hui
il n'y survit pas, et personne ne s'en aperçoit autrement que par le symptôme :
un container recréé rejoue l'onboarding, redemande la connexion, et repose le
dialogue de confiance du projet.

Le constat vient d'une comparaison avec le dev container du dépôt `holotable`,
qui a diagnostiqué et corrigé le même défaut avant nous. Ce document reprend son
diagnostic, corrige l'endroit où le correctif doit être posé, et traite un cas
que ce dépôt-là n'avait pas : plusieurs containers ouverts simultanément sur un
volume de login partagé.

## 2. Le défaut

Le volume `agent-claude` est monté sur `/home/dev/.claude`. Ce montage fonctionne
et n'a jamais été en cause. Il porte `.credentials.json`, `settings.json`,
`plugins/`, `projects/`.

Mais le fichier de configuration principal de Claude Code n'est pas dans ce
répertoire : c'est `~/.claude.json`, un **frère** du répertoire et non un enfant.
Il tombe donc dans la couche inscriptible du container et meurt avec elle. Il
porte :

| Clé | Effet de sa perte |
|---|---|
| `hasCompletedOnboarding` | L'onboarding de premier lancement rejoue |
| `oauthAccount` | L'identité du compte est inconnue |
| `projects[<chemin>].hasTrustDialogAccepted` | Le dialogue de confiance du projet est reposé |
| `projects[<chemin>].allowedTools` | Sans effet en mode YOLO |
| `mcpServers` | Les serveurs MCP déclarés sont perdus |

**Persister le jeton ne suffit pas**, et c'est le point contre-intuitif du
diagnostic : `.credentials.json` est bien dans le volume et survit vraiment,
jeton de rafraîchissement compris. Mais l'identité vit dans `oauthAccount`, côté
`.claude.json`. Un container recréé se retrouve donc jeton valide / identité
inconnue / `hasCompletedOnboarding` absent — et Claude Code rejoue le flux de
première connexion malgré le jeton. La sonde faite sur `holotable` : un
répertoire ne contenant *que* `.credentials.json` rend `loggedIn: true` mais
`email: null`, `orgId: null`, `orgName: null` ; on y ajoute `.claude.json` et les
trois reviennent renseignés.

Détail qui achève de dater le défaut : Claude Code écrivait tout ce temps des
*sauvegardes* de ce fichier dans `/home/dev/.claude/backups/`. Elles persistaient
parfaitement, et n'étaient jamais relues.

## 3. Le correctif

`CLAUDE_CONFIG_DIR=/home/dev/.claude` déplace le fichier de configuration dans le
répertoire que Claude Code utilise déjà par défaut. Rien d'autre ne bouge : les
credentials restent exactement où elles sont, avec désormais à côté d'elles
l'identité qui les rend utilisables.

Le comportement de la variable est **vérifié dans le binaire** (installation
native de l'hôte, lue le 2026-08-14) et non repris de seconde main : le chemin du
fichier de configuration global s'y calcule en `join(CLAUDE_CONFIG_DIR ||
homedir(), '.claude.json')`. La variable désigne bien un répertoire, et le
fichier y est rangé.

**La variable est posée par `ENV` dans `images/agent-base/Dockerfile`**, pas par
`containerEnv` dans le template. Trois raisons :

1. Un `containerEnv` que l'IDE cesserait d'honorer revient vide, et Claude Code
   retombe silencieusement sur `$HOME` — les réglages se remettent à mourir à
   chaque rebuild, sans erreur nulle part. C'est la panne muette que le dépôt
   cherche systématiquement à rendre impossible ; `holotable` la documente comme
   un risque assumé, nous la supprimons.
2. Le point de montage `/home/dev/.claude` est déjà créé et attribué à `dev` dans
   la même image. La variable et le répertoire qu'elle désigne restent sous la
   même autorité.
3. Ce qui est dans l'image est atteignable par `tests/smoke.sh`. Ce qui n'est que
   dans le template ne l'est pas.

`lib/claude-settings.sh` suit la variable plutôt que de recalculer le chemin :
`"${CLAUDE_CONFIG_DIR:-$HOME/.claude}"`. Les deux valeurs coïncident aujourd'hui ;
la forme à repli garantit qu'elles ne peuvent pas diverger demain.

### Alternatives écartées

| Option | Raison du rejet |
|---|---|
| `containerEnv` dans le template | Silencieusement ignorable par l'IDE, et hors de portée du smoke test |
| Volume `.claude` préfixé par projet | `CLAUDE_CONFIG_DIR` déplace tout le répertoire, credentials comprises : le login serait à refaire projet par projet, ce que `agent-claude` partagé évite précisément |

## 4. Écriture concurrente sur un volume partagé

`agent-claude` est partagé entre projets à dessein — se connecter une fois,
installer les plugins une fois. Y faire entrer `.claude.json` soulève une
question : deux containers ouverts en même temps écrivent le même fichier, et ce
dépôt suppose l'usage simultané. C'est un mode de travail courant ici, pas un
accident.

**La question se répond d'elle-même par sa généralité.** Deux containers
partageant ce volume, c'est exactement deux terminaux ouverts sur un poste : même
fichier unique, deux processus, aucune coordination supplémentaire d'un côté ni
de l'autre. Ce n'est donc pas un cas que la conteneurisation invente — c'est le
cas ordinaire de n'importe quel utilisateur de Claude Code, et il serait
notoirement cassé s'il l'était.

Lecture du binaire (installation native de l'hôte, 2026-08-14), qui le confirme
et dit comment :

- L'écriture passe par `saveConfigWithLock`, un **verrou inter-processus**. La
  contention est un cas prévu et instrumenté, jusque dans le message d'attente :
  « Lock acquisition took longer than expected — another Claude instance may be
  running », avec une métrique dédiée.
- **La configuration est relue depuis le disque sous le verrou**, et la
  modification s'applique à cette relecture. Un container n'écrit donc pas la
  vision du monde qu'il avait à son démarrage.
- Un garde refuse explicitement une écriture dont la relecture perdrait
  l'authentification détenue en cache, avec son numéro d'issue amont (GH #3117),
  et une métrique compare mtime et taille entre lecture et écriture.
- Le verrou est `proper-lockfile`, dont la détection de péremption est fondée sur
  la **mtime**, jamais sur les PID. Rien ne dépend donc des namespaces de
  processus : deux containers ont des espaces de PID distincts, mais partagent le
  système de fichiers et l'horloge du noyau hôte, qui est tout ce dont ce verrou
  a besoin.

### Ce que le correctif fait en plus, et qui n'était pas prévu

`proper-lockfile` pose son verrou **à côté du fichier qu'il protège**
(`.claude.json.lock`). Aujourd'hui, la configuration vivant dans `$HOME` hors du
volume, chaque container a donc son propre fichier *et son propre verrou* : deux
instances qui ne se voient pas, chacune se croyant seule. Personne ne l'a jamais
remarqué parce qu'il n'y avait rien à remarquer — l'état mourait de toute façon à
la recréation.

Poser `CLAUDE_CONFIG_DIR` dans le volume n'y met donc pas seulement le fichier :
**ça y met le verrou**. Le partage n'est pas acceptable *malgré* la concurrence,
il est correct *parce que* la concurrence devient visible aux deux instances.

Cela recoupe un autre choix du dépôt : une péremption fondée sur la mtime suppose
un système de fichiers qui l'honore. Un volume Docker natif est de l'ext4, donc
oui. Un bind mount Windows — que le design écarte déjà pour des raisons de
performance — serait le terrain où ce serait douteux.

### Ce qui reste non vérifié

La sémantique exacte de fusion à l'écriture : le code construit l'objet écrit par
comparaison avec un état de référence dont la définition n'a pas été lue.
L'existence même de la métrique d'écriture périmée indique que le cas est mesuré
en amont, donc qu'il n'est pas tenu pour impossible. Et la lecture porte sur la
version installée sur l'hôte, alors que l'image installe `latest` — un
durcissement de cette nature ne régresse pas facilement, mais ce n'est pas une
garantie contractuelle.

## 5. Ce que le correctif fait persister en plus, et qu'on ne voulait pas

La corruption. Ce fichier se corrompt en pratique : `holotable` en a un cas
horodaté, quarantaine en `backups/.claude.json.corrupted.<horodatage>` et retour
à l'état de premier lancement. Jusqu'ici la couche inscriptible effaçait un tel
fichier au rebuild suivant, par accident. Désormais un fichier corrompu survit
comme le reste.

C'est le bon compromis, et la récupération est dans le même répertoire :
`backups/` porte des copies `.claude.json.backup.*`. Le README doit envoyer là
avant de renvoyer vers une reconnexion.

## 6. Migration

Aucune. L'ancien `~/.claude.json` vit dans la couche inscriptible du container
courant et disparaît avec lui : il n'y a rien à recopier au moment où le nouveau
container démarre. Le premier rebuild après la publication rejoue donc
l'onboarding une dernière fois, puis l'état tient.

Un utilisateur qui tient à ne pas le rejouer peut, depuis le container *encore en
cours*, exécuter `cp -p ~/.claude.json ~/.claude/.claude.json` avant de
reconstruire — `-p` parce que le fichier est en mode 600 et porte l'identité du
compte. C'est une note de README, pas du code : automatiser une opération à faire
avant la destruction du container reviendrait à la faire au mauvais moment.

## 7. Vérifications

| Ce qui est vérifié | Par quoi | Portée |
|---|---|---|
| La variable est exportée à tout processus, sans shell | `smoke.sh`, `docker run … printenv` | Prouve la supériorité de `ENV` sur `containerEnv` |
| Elle vaut la cible du montage du template | Test unitaire : `ENV` du Dockerfile ↔ clé de `devcontainer-invariants.cjs` | Attrape la dérive entre image et template |
| Un fichier écrit là survit à la recréation | `smoke.sh`, sur le patron du test d'historique existant | Vérifie la plomberie, **pas** le comportement de Claude Code |
| `claude-settings.sh` suit la variable | `smoke.sh`, avec une valeur détournée | Interdit le retour d'un chemin en dur |
| Claude Code honore réellement la variable | Lecture du binaire (§3), puis vérification manuelle après publication | La lecture prouve le calcul du chemin ; l'aller-retour complet demande une session authentifiée, donc hors CI |

La troisième ligne du tableau est le seul endroit où le smoke test pourrait
donner une fausse assurance : écrire un fichier témoin dans le volume prouve que
le montage et la variable s'accordent, pas que Claude Code écrit là. La
distinction est explicite dans le commentaire du test.

## 8. Amélioration connexe

Une correction tirée de la même comparaison, sans lien technique avec ce qui
précède mais qui relève du même passage de version.

**Le volume est la seule copie du travail.** Le workspace vit dans un volume
Docker, pas sur le disque de l'hôte. Un `docker volume prune`, une remise à zéro
de Docker Desktop ou un volume orphelin après un rebuild raté emporte le travail
non poussé, et aucune sauvegarde de l'hôte ne le couvre. La mise en garde est
plus aiguë ici que dans le dépôt d'origine : le garde-fou bloque `git push`, donc
seul l'humain publie, et la fenêtre d'exposition est structurellement plus
longue. À dire dans le README et dans les trois modes de la skill qui créent ou
recréent un container (« brancher », « amorcer », « migrer ») — ce dernier
opère justement la transition d'un workspace posé sur le disque de l'hôte vers
un volume Docker, donc le risque y est aussi réel que dans les deux autres.

## 9. Hors périmètre, avec les raisons

Trois emprunts possibles au dépôt d'origine, examinés et écartés. Ils sont
consignés pour que la question ne se repose pas.

| Écarté | Raison |
|---|---|
| Cache-bust registre (`ADD https://registry.npmjs.org/…`) avant l'installation de l'agent | Le mécanisme est juste — Docker cle une couche `RUN` sur le texte de l'instruction, donc `@latest` ne se rafraîchit jamais. Mais `publish.yml` ne déclare aucun cache de build : chaque tag reconstruit à froid, et l'image publiée porte l'agent du jour du tag. Le gain se limiterait aux itérations locales de `mise run build-base`, et l'installeur natif ne tirant pas de npm, le document de version ne serait qu'un indicateur indirect |
| Cuire les navigateurs Playwright et les JAR d'émulateurs dans l'image | Le choix des volumes partagés est meilleur : la version suit le lockfile du projet au lieu d'un `ARG` à resynchroniser à la main |
| Reprise en main du prefix npm global, et son garde `REFUSING` | Sans objet : installeur natif dans `~/.local/bin` et mise en user-level, il n'y a rien qui appartienne à root à récupérer |
| `sudo` sans mot de passe conservé pour l'utilisateur | Frontalement contraire à `no-new-privileges`, qui est ce qui rend le garde-fou root-only inatteignable |
| Élargir la liste de ports d'émulateurs | Examiné parce que le dépôt d'origine en publie huit contre quatre ici, et écarté après lecture : `references/brancher.md` §1 porte déjà la table complète (Hosting 5000, Functions 5001, Storage 9199, Pub/Sub 8085, RTDB 9000), `firebase.json` y fait autorité, et les quatre ports du template ne sont que le défaut d'amorçage — UI, Auth, Firestore, plus le port de serve. Seul le hub 4400 n'est nulle part, et il n'a pas à l'être : c'est un point de coordination interne, pas une interface qu'on ouvre |

## 10. Versionnage

Version mineure : `1.2.0`. Aucun projet branché n'a de fichier à modifier, et le
template reste sur le tag `:1`. La règle du README sur le tag du template ne
s'applique qu'aux changements de majeure.

`plugin/.claude-plugin/plugin.json` et `.claude-plugin/marketplace.json` sont
alignés sur cette version, comme le vérifie déjà
`tests/unit/plugin-manifests.test.cjs`.

## 11. Limites assumées

- Le correctif ne s'arme qu'à la **recréation** du container, pas dans celui en
  cours : un `ENV` d'image est fixé à la construction.
- La coordination entre containers simultanés repose sur `proper-lockfile` et sur
  une relecture sous verrou, l'un et l'autre lus dans le binaire mais pas
  éprouvés ici en conditions réelles. La sémantique fine de fusion reste hors de
  ce qui a été vérifié (§4).
- Une configuration corrompue survit désormais aux rebuilds. La récupération est
  documentée, elle n'est pas automatique.
