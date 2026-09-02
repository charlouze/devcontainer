# Outillage GCP : ce que le dev container permet, et ce qu'il ne permettra pas

Date : 2026-09-02
État : design validé, prêt pour la planification d'implémentation

## 1. Objectif

Un projet à venir hébergera des serveurs de jeu sur Compute Engine, piloté par
une interface Firebase. La demande initiale était « un dev container qui sache
construire une image Docker et l'envoyer sur GCP ».

Ce design répond deux choses. D'abord que la construction d'une image OCI dans
ce dev container est impossible sans en démonter le dispositif de sécurité — ce
n'est pas une opinion, c'est un résultat de mesure, consigné en §3. Ensuite que
l'outillage manquant ne justifie **aucune nouvelle image** : l'image `web`
existante couvre déjà la partie Firebase, et le reste relève du `mise.toml` du
projet consommateur, conformément au critère posé par le design d'origine.

Le travail qui reste dans ce dépôt est donc un travail de bornes et de
documentation : rendre explicite ce qui était implicite, et fermer un trou
découvert en chemin.

## 2. Périmètre

Dans le périmètre :

- une règle de garde-fou couvrant les commandes Terraform qui écrivent ;
- un invariant fermant la liste des valeurs acceptées pour `--security-opt` ;
- la mise en cohérence de `/etc/subuid` et `/etc/subgid` ;
- une section de README consignant ce que le container ne sait pas faire ;
- le même rappel dans la skill d'onboarding, seul endroit lu par qui branche un
  projet ;
- la publication d'une version 1.6.0.

Hors périmètre :

- **Une troisième image.** §4 explique pourquoi elle n'a pas lieu d'être.
- **Le dépôt du système d'hébergement lui-même** — son Terraform, son front
  Firebase, sa chaîne de build et de déploiement. Il aura son propre cycle de
  conception. §7 note ce qu'il faudra en retenir.
- **Un cache partagé de providers Terraform.** Le raisonnement serait celui du
  store pnpm, mais avec un seul projet Terraform le gain est nul et le coût
  réel : septième montage, `MONTAGES_PARTAGES`, template, liste de contrôle. À
  reprendre le jour où un deuxième projet Terraform existe.

## 3. Le résultat qui structure le design

Sonde exécutée le 2026-09-02 : buildah 1.28.2 en rootless, dans l'image
`ghcr.io/charlouze/devcontainer-web:1`, sur Docker 29.6.2 (Docker Desktop,
Windows). Trois builds gradués — `FROM scratch` + `COPY`, `FROM debian` +
`RUN echo`, `FROM debian` + `apt-get install` — sous des configurations
croissantes de permissivité.

| Configuration | user namespace | `FROM scratch` | avec `apt-get` |
|---|---|---|---|
| `runArgs` du template | refusé | non | non |
| `docker run` nu, sans aucune option | refusé | non | non |
| `+ seccomp=unconfined`, user `dev` | ok | oui | non |
| idem + subuid renseigné pour `dev` | ok | oui | non |
| idem sans `no-new-privileges`, caps par défaut | ok | oui | non |
| `seccomp=unconfined`, user `root` | ok | oui | **oui** |

Deux enseignements, et le premier corrige une intuition fausse.

**Le durcissement du dépôt n'est pas en cause.** Ni `no-new-privileges` ni
`--cap-drop ALL` ne bloquent la création du user namespace : c'est le profil
seccomp par défaut de Docker, qui refuse `unshare(CLONE_NEWUSER)`. Un
`docker run` sans la moindre option échoue identiquement. Retirer du
durcissement ne rendrait donc rien.

**Le second verrou, lui, ne s'ouvre que par root.** Une fois seccomp levé,
`newuidmap` rend `Operation not permitted` — y compris sans
`no-new-privileges` et avec les capabilities Docker par défaut. buildah retombe
sur un mapping à un seul UID (`0 1000 1`), et le simple *pull* de
`debian:bookworm-slim` échoue sur `/etc/gshadow`, dont le gid 42 n'existe pas
dans ce mapping. La seule case qui construit est `user root` +
`seccomp=unconfined`.

Or root rend le garde-fou atteignable : `/etc/claude-guard/enabled` est en 0444
root, donc supprimable par root, et `managed-settings.json` avec lui. Construire
en local et confiner l'agent s'excluent. Le déploiement passera par la CI, la
construction locale aussi.

## 4. Décisions structurantes

| Décision | Retenu | Raison |
|---|---|---|
| Nouvelle image | Non | `web` couvre Firebase ; Terraform et hadolint sont des outils épinglés par projet |
| Outillage Terraform | `mise.toml` du projet | Critère du design d'origine : l'image accélère, elle ne contraint pas |
| `gcloud` dans l'image | Non | Le garde-fou le bloque ; l'installer produirait un outil présent et inutilisable, donc un piège |
| Règle Terraform | Dans le socle | Même raison que `gcloud` : c'est une borne du dispositif, pas une préférence de dépôt |
| Trou seccomp | Extension de `runargs-securite` | Même préoccupation que l'invariant existant ; un dixième invariant découperait ce qui se tient |
| `/etc/subuid` | Vidé, pas renommé | Un fichier vide dit l'intention ; un fichier renommé ne dit que le nom |

## 5. Ce qui change dans ce dépôt

### 5.1 Règle de garde-fou pour Terraform

Dans `images/agent-base/guard/rules.cjs`, à la suite de la règle `gcloud`. Deux
entrées, parce que les sous-commandes d'état ont un mot de plus :

```js
[
  /(^|[\s;&|(])(terraform|tofu)\s+(?:-\S+\s+)*(apply|destroy|import|force-unlock|taint|untaint)\b/,
  "Les commandes Terraform qui écrivent sont bloquées. `init`, `fmt`, " +
    '`validate`, `plan` et `show` restent disponibles.',
],
[
  /(^|[\s;&|(])(terraform|tofu)\s+(?:-\S+\s+)*state\s+(rm|mv|push|replace-provider)\b/,
  "Réécrire l'état Terraform est bloqué : c'est le moyen détourné de " +
    'changer l\'infrastructure sans passer par un `apply`.',
],
```

Le préfixe `(?:-\S+\s+)*` absorbe les options globales, qui se glissent entre la
commande et le verbe. Ce n'est pas décoratif : `terraform -chdir=infra apply`
est la forme ordinaire dès que le Terraform vit dans un sous-répertoire, et sans
ce groupe elle passerait sous les deux règles. Même raisonnement que le préfixe
des règles `git push` existantes.

`plan` reste libre. Sans Application Default Credentials il échouera de
lui-même ; le laisser passer évite d'écrire une règle qui prétend protéger ce
que l'absence de credential protège déjà.

Ces deux motifs ont été vérifiés le 2026-09-02 sur 25 commandes : les treize
formes visées sont bloquées, `-chdir` et enchaînements par `;`, `&&` ou
parenthèse compris, et les douze formes de lecture passent — `plan`, `init`,
`fmt`, `validate`, `show`, `state list`, `state show`, ainsi que
`cat notes-terraform.md`.

Limite connue, partagée avec les règles existantes : le garde-fou ne lit qu'une
ligne de commande, sans savoir ce qui est du code et ce qui est du texte. Un
`git commit -m 'ajoute terraform apply au runbook'` sera refusé. C'est le même
compromis que pour `gcloud`, et le contourner demanderait au garde-fou de parser
le shell — un coût sans rapport avec le gain.

Tests à ajouter dans `tests/unit/rules.test.cjs`, sur le modèle des tests
`gcloud` : bloque `terraform apply -auto-approve`, bloque
`terraform -chdir=infra destroy`, bloque `terraform state rm foo`, ne bloque ni
`terraform plan` ni `terraform fmt -check` ni `cat notes-terraform.md`.

### 5.2 Fermeture du trou seccomp

`tests/lib/devcontainer-invariants.cjs` ne contraint aujourd'hui que la
*présence* de `--security-opt no-new-privileges`. Un
`"--security-opt", "seccomp=unconfined"` ajouté à côté passe les neuf invariants
et toute la CI sans un mot — et c'est précisément l'option qui ouvre les user
namespaces, donc la seule qui rapproche d'un chemin d'évasion. Le trou est en
face de la serrure.

Correction : une constante `SECURITY_OPTS_AUTORISEES = ['no-new-privileges']`,
et dans la boucle qui parcourt déjà les paires de `runArgs`, un refus
`runargs-securite` sur toute valeur de `--security-opt` hors liste.

Conséquence assumée : la forme `no-new-privileges:true`, que Docker accepte,
sera refusée. C'est cohérent avec le contrôle de présence existant, qui exige
déjà la chaîne exacte, et l'uniformité vaut mieux ici que la tolérance.

Le libellé de l'invariant `runargs-securite` change, donc la ligne
correspondante de la liste de contrôle de
`plugin/skills/onboard-devcontainer/SKILL.md` change avec lui. Attention : rien
ne l'impose mécaniquement. `tests/unit/skill-checklist.test.cjs` ne vérifie que
la **présence de l'identifiant** dans la prose — `skill.includes(\`${id}\`)` —
et l'identifiant ne change pas ici. Une liste de contrôle laissée en arrière
passerait donc la CI en silence. C'est une raison de plus de ne pas renommer
l'invariant : un identifiant neuf aurait fait échouer le test, donc rappelé la
prose à l'ordre, mais au prix de découper en deux ce qui est une seule
préoccupation.

Un test à ajouter dans `tests/unit/devcontainer-invariants.test.cjs` : un
`devcontainer.json` par ailleurs conforme, mais portant `seccomp=unconfined`,
doit produire une violation.

### 5.3 `/etc/subuid` et `/etc/subgid`

`images/agent-base/Dockerfile` renomme `vscode` en `dev` par `usermod --login`,
qui ne met pas à jour ces deux fichiers : ils portent encore
`vscode:100000:65536`. Personne ne les lit aujourd'hui, mais le nom d'un
utilisateur qui n'existe plus est une amorce de confusion.

Les **vider** plutôt que les renommer, juste après le bloc `usermod` :

```dockerfile
# usermod --login ne suit pas /etc/subuid ni /etc/subgid, qui portaient encore
# `vscode`. On les vide plutôt que de les renommer : une plage subuid n'a aucun
# usage dans un container qui ne doit jamais créer de user namespace, et un
# fichier vide est un second verrou là où un fichier renommé n'aurait été
# qu'une cohérence de nom.
RUN : > /etc/subuid && : > /etc/subgid
```

Vider et non supprimer : certains outils distinguent mal le fichier absent du
fichier vide, et l'absence n'apporte rien de plus.

Assertion à ajouter dans `tests/smoke.sh` : les deux fichiers existent et sont
vides. C'est ce qui empêche une mise à jour de l'image de base de les
réintroduire en silence.

### 5.4 Section de README

Le README a une section « Ce que le garde-fou ne protège pas », dont la valeur
tient à ce qu'elle nomme les limites au lieu de les taire. Lui donner son
pendant : **« Ce que le container ne sait pas faire »**, portant le tableau de
§3, la conclusion, et surtout le fait que le blocage vient du profil seccomp par
défaut de Docker et non du durcissement du dépôt. Sans cette précision, la
prochaine personne qui butera dessus retirera du durcissement en espérant que ça
débloque, et perdra la même journée.

Y mentionner aussi l'orientation qui en découle : le container rédige et vérifie
statiquement, la CI construit et déploie.

### 5.5 Rappel dans la skill d'onboarding

Le README de §5.4 est lu par qui travaille sur ce dépôt-ci. Il ne l'est pas par
qui branche un projet : cette personne lit la skill. Or sur un dépôt dont le
cœur est d'héberger des serveurs de jeu, la première chose sur laquelle elle
butera est un `docker build` qui ne marche pas.

`plugin/skills/onboard-devcontainer/SKILL.md` se termine par un paragraphe qui
rappelle ce que le garde-fou **ne** protège **pas**. C'est le bon endroit et le
bon moment : y ajouter que le container ne construit pas d'image OCI, que la
raison est le profil seccomp par défaut de Docker et non le durcissement, et que
la construction comme le déploiement se font en CI.

`references/amorcer.md` §4 le répète, brièvement. Redondant en apparence, mais
« amorcer » est le mode des projets qui naissent, donc celui que lit quelqu'un
qui ne connaît pas encore le dispositif — et celui où la question du build se
pose le plus tôt. C'est déjà la logique de la section, qui redit là l'avertissement
sur le volume Docker « plus aigu ici que dans les autres modes ».

Aucun test ne couvre ce paragraphe de clôture : `tests/unit/skill-checklist.test.cjs`
ne tient que la liste de contrôle et les renvois par mode. C'est donc, avec le
README, le second livrable à relire à l'œil.

### 5.6 Version 1.6.0

Les points 5.1 et 5.3 touchent l'image, 5.2 et 5.5 touchent le plugin : la
version bouge des deux côtés à la fois, ce qui est le cas normal ici puisqu'elle
est commune. `marketplace.json` et `plugin/.claude-plugin/plugin.json` portent la
même valeur — `tests/unit/plugin-manifests.test.cjs` l'impose. Le tag du
`devcontainer.template.json` reste `:1`, la majeure ne changeant pas.

## 6. Ce qui revient au projet consommateur

Rien à livrer ici, mais le design ne tient que si cette part est claire. Le
projet déclare son outillage dans son propre `mise.toml` :

```toml
[tools]
node = "22"
pnpm = "latest"
terraform = "1.9"
hadolint = "latest"

[tasks.setup]
run = ["pnpm install", "terraform -chdir=infra init -backend=false"]
```

`init -backend=false`, puis `validate` et `fmt`, fonctionnent sans credential :
c'est le périmètre « rédiger et vérifier » retenu en §3. `mise` étant en
user-level, ces versions s'installent sans toucher à l'image — c'est exactement
ce que le design d'origine appelait garder l'autonomie du `mise.toml` du projet.

## 7. Notes pour le dépôt d'hébergement

À reprendre lors de sa propre conception, et consigné ici parce que c'est
maintenant qu'on le sait :

- La construction de l'image du serveur de jeu et son déploiement se font en CI.
  Authentification par Workload Identity Federation plutôt que par clé de compte
  de service : le garde-fou refuse déjà de lire un fichier
  `*serviceaccount*.json`, et une clé de compte de service dans un dépôt est ce
  que cette règle existe pour rendre impensable.
- Le PAT du container n'a pas la permission `Workflows`. GitHub refuse tout push
  touchant `.github/workflows/` : le workflow de déploiement s'écrit depuis le
  poste, pas depuis le container. C'est la barrière structurelle du dispositif,
  pas un accident de configuration.
- Cible retenue : Compute Engine, une VM par serveur. Ni Cloud Run, qui ne fait
  pas d'UDP ni d'état persistant, ni GKE + Agones, dont le coût fixe et la
  complexité ne se justifient pas à cette échelle.
- La skill d'onboarding couvre ce dépôt sans modification : vide, il tombe dans
  le mode « amorcer », cas nominal, que le préambule de `references/amorcer.md`
  décrit comme « un répertoire réellement vide, destiné à Nx + Firebase ». Le
  déroulé
  s'applique tel quel — container d'abord, puis `pnpm create nx-workspace` et
  `firebase init` dedans, puis relance en mode « mettre à jour ». Deux points à
  ne pas corriger au passage : l'identifiant reste `demo-<slug>` et non le vrai
  projet GCP, parce que c'est ce préfixe qui interdit au SDK d'atteindre un
  backend réel ; et Terraform reste absent de ce que la skill écrit, la §6
  ci-dessus étant à saisir à la main.

## 8. Vérification

- `mise run test-unit` — les tests de règles, d'invariants, de manifestes et de
  liste de contrôle, y compris ceux ajoutés en 5.1 et 5.2.
- `mise run check` — la séquence complète de la CI, build des deux images
  compris, puis `tests/smoke.sh` avec l'assertion de 5.3.
- Relecture manuelle des trois livrables que rien ne vérifie mécaniquement : la
  ligne `runargs-securite` de la liste de contrôle de la skill (5.2), la section
  de README (5.4) et le rappel dans la skill (5.5). Les deux dernières sont de
  la prose ; la première est une garantie que la CI ne rattrapera pas.
