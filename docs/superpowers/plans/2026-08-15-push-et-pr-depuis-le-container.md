# Pousser et ouvrir des PR depuis le container — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permettre à l'agent de pousser des branches et d'ouvrir des pull requests depuis le container, le merge restant un geste humain, et distribuer à tous les projets les conventions d'écriture des commits et des corps de PR.

**Architecture:** Le jeton n'entre ni par un fichier de l'hôte ni par une variable : `gh` range son état dans `~/.config/gh`, on y monte un volume partagé `agent-gh`, et l'humain se connecte une fois par `gh auth login --with-token`. Le garde-fou cesse de bloquer `git push` en bloc et passe `gh` en liste blanche — il devient une barrière molle, ce que la documentation doit dire franchement puisque le jeton présent dans le container est utilisable hors de `git` et `gh` (spec §2). Les conventions vivent dans un fichier root-only de l'image, rattaché au `CLAUDE.md` du volume par une ligne d'import.

**Tech Stack:** Dockerfile, bash, Node.js `node:test`, jq, gh CLI, Docker, mise, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-15-push-et-pr-depuis-le-container-design.md`

**Plans précédents:** `2026-08-14-persistance-etat-claude.md`, exécuté et publié en `v1.2.0`. Ce plan-ci en reprend la mécanique d'accord image ↔ template, mais **pas** sa variable d'environnement : ici il n'y en a pas besoin, et c'est un point de conception, pas un oubli (spec §3).

## Global Constraints

- **Langue.** Commentaires, messages, contenu des skills et sorties utilisateur en **français**. Convention du dépôt, elle prime sur l'usage anglophone de l'écosystème.
- **Fins de ligne.** LF partout (`.gitattributes` en place).
- **Messages de commit** : en français, descriptifs, sans préfixe conventionnel (`feat:`, `docs:`, …). **Aucune mention d'assistant** : ni `Co-Authored-By`, ni `Claude-Session`, ni « Generated with ».
- **Le chemin `/home/dev/.config/gh` est à l'octet près**, partout où il apparaît : `mkdir` du `Dockerfile`, `MONTAGES_PARTAGES` de `tests/lib/devcontainer-invariants.cjs`, montage du template, et les quatre fixtures attendues. Une divergence donne un point de montage que `gh` n'utilise pas, et la connexion meurt à chaque recréation sans que rien ne le signale.
- **Le nom du volume est `agent-gh`.** Le préfixe `agent-` n'est pas décoratif : c'est lui qui range le volume dans la famille des montages partagés entre projets, et l'invariant `volumes` le vérifie.
- **Le garde-fou reste une barrière molle et doit être décrit comme telle.** Aucun texte produit par ce plan ne doit laisser croire que `main` ou le merge sont protégés par construction (spec §2). Les seules garanties structurelles sont la portée du PAT et les permissions non accordées.
- **Version du plugin = version des images = `1.3.0`**, à porter dans `plugin/.claude-plugin/plugin.json` et `.claude-plugin/marketplace.json`. Le template reste sur le tag `:1` : ce n'est pas un changement de majeure.
- **Sous Windows, tout ce qui touche Docker se lance depuis Git Bash.** Dans PowerShell, `bash` résout vers le lanceur WSL et échoue.

---

## Structure des fichiers

| Fichier | Responsabilité | Statut |
|---|---|---|
| `images/agent-base/guard/rules.cjs` | Push par branche, `gh` en liste blanche | Modifié |
| `tests/unit/rules.test.cjs` | Formes autorisées et refusées de `git push` et `gh` | Modifié |
| `images/agent-base/Dockerfile` | `gh` installé, point de montage `~/.config/gh`, conventions copiées | Modifié |
| `images/agent-base/lib/github-auth.sh` | Connexion git ↔ gh et identité de commit | Créé |
| `images/agent-base/etc/conventions.md` | Les conventions distribuées, root-only | Créé |
| `images/agent-base/lib/claude-conventions.sh` | Rattache les conventions au `CLAUDE.md` du volume | Créé |
| `images/agent-base/post-create.sh` | Appelle les deux nouveaux scripts, message de fin à jour | Modifié |
| `tests/smoke.sh` | `gh` présent, dégradation sans connexion, idempotence de l'import, nouvelles règles | Modifié |
| `plugin/skills/onboard-devcontainer/references/devcontainer.template.json` | Montage `agent-gh` | Modifié |
| `tests/lib/devcontainer-invariants.cjs` | `agent-gh` dans `MONTAGES_PARTAGES` | Modifié |
| `tests/fixtures/onboarding/*/attendu/devcontainer.json` | Le montage et ses commentaires (4 fichiers) | Modifiés |
| `plugin/skills/onboard-devcontainer/references/github.md` | Étape credentials : PAT, connexion, tentative de ruleset | Créé |
| `plugin/skills/onboard-devcontainer/SKILL.md` | Route vers la nouvelle référence, liste de contrôle, limites du garde-fou | Modifié |
| `plugin/skills/onboard-devcontainer/references/{brancher,amorcer,migrer,mettre-a-jour}.md` | Renvoi vers l'étape credentials, avertissement corrigé | Modifiés |
| `README.md` | Principe affiché, section « pousser », limites, workspace | Modifié |
| `plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | Version `1.3.0` | Modifiés |

**Ordre d'exécution.** Les tâches 1 à 3 sont indépendantes entre elles et peuvent être menées en parallèle : elles ne partagent aucun fichier. La tâche 4 ne dépend que de la 2 (le point de montage doit exister dans l'image avant que le template ne le monte). Les tâches 5 et 6 documentent ce que les précédentes produisent. La tâche 7 publie.

**Attention aux tests existants qui vont casser, et c'est normal.** Trois assertions actuelles affirment que `git push` nu est bloqué : `tests/unit/rules.test.cjs:16`, `:58`, `:65`, et la constante `PUSH` de `tests/smoke.sh:60`. Elles ne décrivent plus le comportement voulu. Elles se **corrigent**, elles ne se suppriment pas : la forme à bloquer devient `git push origin main`.

---

## Task 1: Le garde-fou — push par branche, `gh` en liste blanche

Livrable : `git push` sur une branche passe, `main` et les formes qui publient trop sont refusées, et `gh` n'ouvre que ce qui sert à créer et modifier une PR.

**Files:**
- Modify: `tests/unit/rules.test.cjs`
- Modify: `images/agent-base/guard/rules.cjs:16-51` (`BASH_RULES`)
- Modify: `tests/smoke.sh:60-81` (section « Garde-fou »)

**Interfaces:**
- Consomme : `evaluate(payload, projectRules)` de `images/agent-base/guard/rules.cjs`, signature inchangée
- Produit : rien de nouveau à l'export. Le module reste pur — pas d'accès disque, pas de lecture d'environnement

- [ ] **Step 1: Remplacer les tests de `git push` par ceux du nouveau comportement**

Dans `tests/unit/rules.test.cjs`, remplacer le premier test (l. 15-17) par les quatre suivants :

```js
test('git push sur une branche passe', () => {
  assert.strictEqual(evaluate(bash('git push -u origin ma-branche'), null), null);
});

test('git push sur main est bloqué sous toutes ses formes', () => {
  for (const commande of [
    'git push origin main',
    'git push origin HEAD:main',
    'git push --force origin refs/heads/main',
    'git push origin :master',
  ]) {
    assert.ok(evaluate(bash(commande), null), commande);
  }
});

// La règle vise une référence entière, pas une sous-chaîne : une branche dont le
// nom commence par « main » est un cas ordinaire, la bloquer serait un faux
// positif quotidien.
test('une branche dont le nom commence par main passe', () => {
  assert.strictEqual(evaluate(bash('git push origin main-de-fer'), null), null);
});

test('les formes qui publient plus que la branche sont bloquées', () => {
  for (const commande of [
    'git push --all origin',
    'git push --mirror',
    'git push --tags origin',
    'git push --delete origin vieille-branche',
  ]) {
    assert.ok(evaluate(bash(commande), null), commande);
  }
});
```

- [ ] **Step 2: Ajouter les tests de la liste blanche `gh`**

Dans le même fichier, à la suite des précédents :

```js
test('gh ouvre et modifie des pull requests', () => {
  assert.strictEqual(evaluate(bash('gh pr create --title x --body y'), null), null);
  assert.strictEqual(evaluate(bash('gh pr edit 12 --body z'), null), null);
  assert.strictEqual(evaluate(bash('gh pr view 12'), null), null);
});

// Le refus par défaut est la propriété qui compte : une liste noire laisserait
// passer `gh api`, qui contourne toute énumération, et toute sous-commande que
// gh ajoutera demain.
test('gh ne merge pas, et le reste est refusé par défaut', () => {
  for (const commande of [
    'gh pr merge 12',
    'gh pr close 12',
    'gh api repos/o/d/pulls/1/merge --method PUT',
    'gh secret set CLE',
    'gh sous-commande-inconnue',
  ]) {
    assert.ok(evaluate(bash(commande), null), commande);
  }
});
```

- [ ] **Step 3: Corriger les deux tests qui poussent nu**

Toujours dans `tests/unit/rules.test.cjs`, aux tests « les règles projet ne peuvent pas lever un interdit du socle » (l. 56-59) et « un fichier de règles illisible laisse le socle intact et avertit » (l. 61-66), remplacer les deux occurrences de :

```js
  assert.ok(evaluate(bash('git push'), rules));
```

par :

```js
  assert.ok(evaluate(bash('git push origin main'), rules));
```

`git push` nu est désormais autorisé : laissé tel quel, chaque test affirmerait le contraire de ce que le socle fait, et échouerait pour la mauvaise raison.

- [ ] **Step 4: Lancer les tests et vérifier qu'ils échouent**

Run: `mise run test-unit`
Expected: FAIL. « git push sur une branche passe » échoue — la règle actuelle bloque tout `git push`. « gh ouvre et modifie des pull requests » passe déjà par accident (la liste noire actuelle ne couvre pas `gh pr`), et « gh ne merge pas » échoue sur `gh pr merge`, `gh api` et la sous-commande inconnue.

- [ ] **Step 5: Réécrire les règles**

Dans `images/agent-base/guard/rules.cjs`, remplacer la règle `git push` (l. 17-21) par les deux suivantes :

```js
  [
    /\bgit\s+push\b[^\n;&|]*(?<=[\s:]|refs\/heads\/)(main|master)(?=\s|$)/,
    'Pousser sur main est bloqué : ouvre une branche et une pull request. ' +
      "L'intégration est un geste humain, dans l'interface GitHub.",
  ],
  [
    /\bgit\s+push\b[^\n;&|]*\s(--all|--mirror|--tags|--delete|-d)\b/,
    'Cette forme de git push publie plus que la branche courante — toutes les ' +
      'branches, tous les tags — ou supprime une référence distante. Pousse ' +
      'une branche nommée.',
  ],
```

Trois détails portent tout le comportement :

- `[^\n;&|]*` borne la recherche à **une seule commande** : sans lui, `git push origin ma-branche && echo main` serait bloqué par le mot `main` de la commande suivante.
- Le lookbehind `(?<=[\s:]|refs\/heads\/)` et le lookahead `(?=\s|$)` exigent une **référence entière**. `main-de-fer` n'est pas `main`, et `feature/main` non plus — ce dernier est un choix : seul `refs/heads/` est reconnu comme préfixe de référence.
- Dans `(--all|--mirror|--tags|--delete|-d)`, `--delete` précède `-d` : l'alternation rend la première branche qui matche, et l'ordre inverse ferait consommer `-d` au début de `--delete`, laissant un `\b` qui échoue.

Puis remplacer la règle `gh` (l. 40-43) par :

```js
  [
    /\bgh\s+(?!(pr\s+(create|edit|view|list|diff|status|checkout|comment|ready)|issue\s+(view|list|create|edit|comment)|repo\s+view|auth\s+status|browse|search|--version|--help)\b)/,
    'Seules la création, la modification et la lecture de pull requests sont ' +
      'ouvertes à gh. Le merge, la fermeture, `gh api` et le reste sont refusés ' +
      "par défaut — l'intégration est un geste humain.",
  ],
```

C'est un **lookahead négatif**, donc une liste blanche : tout ce qui n'est pas nommé est bloqué, y compris les sous-commandes que `gh` ajoutera plus tard. `gh auth login` en fait partie et c'est voulu : la connexion se fait à la main, le jeton passant par stdin (spec §3).

- [ ] **Step 6: Relancer les tests unitaires**

Run: `mise run test-unit`
Expected: PASS, les 19 tests du fichier compris.

- [ ] **Step 7: Mettre le smoke test en accord**

Dans `tests/smoke.sh`, remplacer la constante `PUSH` (l. 60) et ajouter trois payloads :

```bash
PUSH='{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
PUSH_BRANCHE='{"tool_name":"Bash","tool_input":{"command":"git push -u origin ma-branche"}}'
GH_PR='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title x --body y"}}'
GH_MERGE='{"tool_name":"Bash","tool_input":{"command":"gh pr merge 12"}}'
```

`PUSH` reste le payload bloquant utilisé par les deux vérifications de contournement (environnement vidé, injection `NODE_OPTIONS`, l. 72-81) : elles ont besoin d'une commande qui **doit** sortir en 2, et c'est maintenant celle-ci. Ne pas y toucher autrement.

Puis, dans la section « Garde-fou », remplacer la ligne `check "git push est bloqué"` (l. 65) par :

```bash
check  "git push sur main est bloqué"             blocks "$PUSH"
check  "git push sur une branche passe"           allows "$PUSH_BRANCHE"
check  "gh pr create passe"                       allows "$GH_PR"
check  "gh pr merge est bloqué"                   blocks "$GH_MERGE"
```

- [ ] **Step 8: Construire l'image de base et lancer le smoke test**

Run: `mise run build-base && mise run build-web && mise run test-smoke`
Expected: les quatre vérifications de la section « Garde-fou » en `ok`, et les deux vérifications de contournement toujours en `ok`.

- [ ] **Step 9: Commit**

```bash
git add images/agent-base/guard/rules.cjs tests/unit/rules.test.cjs tests/smoke.sh
git commit -m "Le garde-fou autorise le push par branche et n'ouvre gh qu'aux pull requests"
```

---

## Task 2: `gh` dans l'image, et la connexion qui survit aux recréations

Livrable : `gh` est installé, le point de montage de sa configuration existe avec le bon propriétaire, et le provisionnement connecte git au compte — ou dit clairement comment se connecter.

**Files:**
- Modify: `images/agent-base/Dockerfile:32-38` (bloc `mkdir`) et après l. 90 (installation de `claude`)
- Create: `images/agent-base/lib/github-auth.sh`
- Modify: `images/agent-base/post-create.sh:8-13` et son message de fin
- Modify: `tests/smoke.sh` (section « Utilisateur et toolchain », et « Provisionnement »)

**Interfaces:**
- Consomme : `gh` sur le `PATH` via les shims mise, `jq` déjà présent dans l'image
- Produit :
  - `/usr/local/share/devcontainer/lib/github-auth.sh`, exécutable, **sort toujours en 0**
  - `/home/dev/.config/gh`, répertoire appartenant à `dev`, destiné au montage `agent-gh`

- [ ] **Step 1: Créer le point de montage dans l'image**

Dans `images/agent-base/Dockerfile`, ajouter une ligne au bloc `mkdir -p` (l. 32-38), avant le `chown -R` :

```dockerfile
RUN mkdir -p /home/${USERNAME}/.claude \
             /home/${USERNAME}/.cache \
             /home/${USERNAME}/.cache/pnpm-store \
             /home/${USERNAME}/.cache/ms-playwright \
             /home/${USERNAME}/.config/gh \
             /home/${USERNAME}/.history \
             /home/${USERNAME}/.local/bin \
 && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}
```

Le commentaire qui précède le bloc explique déjà pourquoi : un chemin absent de l'image donne un point de montage `root:root`, et `dev` ne peut alors rien y écrire — ici, `gh auth login` échouerait.

- [ ] **Step 2: Installer `gh`**

Dans le même fichier, après l'installation de `claude` (l. 90) et avant le `printf` de l'alias `yolo` :

```dockerfile
# gh sert à ouvrir et modifier des pull requests depuis la session. En
# user-level comme le reste de la toolchain : rien de ce que l'agent utilise au
# quotidien n'a à appartenir à root.
#
# Sa configuration vit dans ~/.config/gh, l'emplacement par défaut — c'est ce
# qui permet au template d'y monter un volume sans poser la moindre variable
# d'environnement, donc sans rien qu'un IDE puisse ignorer en silence.
RUN mise use --global --yes gh@latest
```

- [ ] **Step 3: Vérifier que `gh` s'installe réellement**

Run: `mise run build-base && docker run --rm -u dev devcontainer-agent-base:dev bash -lc 'gh --version'`
Expected: une version de `gh` s'affiche.

Si `mise` ne résout pas `gh` (backend absent du registre de la version embarquée), replier sur le dépôt apt de GitHub CLI, dans la couche `USER root` — et **le dire dans le commit** plutôt que de laisser croire que le user-level a été retenu :

```dockerfile
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*
```

- [ ] **Step 4: Écrire `github-auth.sh`**

Créer `images/agent-base/lib/github-auth.sh` :

```bash
#!/usr/bin/env bash
# Connecte git au compte GitHub, si le volume porte déjà une connexion gh.
#
# Le jeton n'entre jamais par ici : la connexion est un geste humain, fait une
# fois (`gh auth login --with-token`), et le volume `agent-gh` la garde d'un
# container à l'autre. Ce script ne fait que recâbler ce qui ne persiste pas —
# ~/.gitconfig vit dans la couche inscriptible.
#
# Sort toujours en 0 : post-create.sh tourne sous `set -e`, et l'absence de
# connexion est un état normal, pas une erreur.
set -uo pipefail

warn() { printf '\033[1;33m /!\\ %s\033[0m\n' "$1" >&2; }

if ! command -v gh >/dev/null 2>&1; then
  warn "gh est introuvable : ni push ni pull request depuis cette session."
  exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
  cat <<'EOF'
GitHub : non connecté. Une fois pour toutes, dans ce terminal :

    gh auth login --with-token

puis colle le jeton et Ctrl-D. Il passe par stdin, donc il n'entre pas dans
l'historique de shell — et le volume agent-gh le garde d'une recréation à
l'autre.
EOF
  exit 0
fi

# git emprunte l'authentification de gh : un seul mécanisme pour les deux
# outils, et aucune variable d'environnement dans la boucle — l'outil Bash de
# l'agent n'est ni interactif ni un shell de login, il ne lirait ni
# /etc/profile.d ni /etc/bash.bashrc.
gh auth setup-git

# Un seul appel réseau, dont on tolère l'échec : sans réseau, la connexion reste
# utilisable, seule l'identité manque. La renseigner est ce qui rend le premier
# commit possible — sans user.email, git refuse de commiter.
if utilisateur="$(gh api user 2>/dev/null)" && [ -n "$utilisateur" ]; then
  login="$(printf '%s' "$utilisateur" | jq -r '.login')"
  identifiant="$(printf '%s' "$utilisateur" | jq -r '.id')"
  nom="$(printf '%s' "$utilisateur" | jq -r '.name // .login')"

  # L'adresse noreply du compte, jamais l'adresse publique : elle suffit à ce
  # que GitHub attribue les commits, sans publier d'adresse personnelle dans
  # l'historique de tous les dépôts touchés.
  git config --global user.name "$nom"
  git config --global user.email "${identifiant}+${login}@users.noreply.github.com"
  echo "GitHub : connecté comme ${login}"
else
  warn "Connexion gh présente, mais l'API est injoignable : identité git non posée."
fi

exit 0
```

- [ ] **Step 5: L'appeler depuis le provisionnement**

Dans `images/agent-base/post-create.sh`, ajouter une ligne après « Git » (l. 13) :

```bash
say "Identité";            "$lib/identity.sh"
say "Toolchain mise";      mise trust --yes && mise install --yes
say "Store pnpm";          "$lib/configure-pnpm.sh"
say "Réglages Claude";     "$lib/claude-settings.sh"
say "Plugins";             "$lib/install-plugins.sh"
say "Git";                 git config --global --add safe.directory "$PWD"
say "GitHub";              "$lib/github-auth.sh"
```

Puis remplacer le bloc de garde-fous du message de fin (l. 31-36) par :

```bash
  Garde-fous actifs dans ce container :
    - aucun credential Google/GCP : le SDK Admin ne peut viser que l'émulateur
    - firebase deploy, gcloud, publish npm : bloqués par hook
    - git push : ouvert sur une branche, bloqué sur main
    - gh : création et modification de PR seulement, jamais le merge
    - non-root, capabilities Linux réduites, pas de socket Docker
    - règles projet : $( [ -f "$regles" ] && echo "chargées depuis $regles" || echo "aucune" )
```

- [ ] **Step 6: Vérifier au niveau container**

Dans `tests/smoke.sh`, section « Utilisateur et toolchain », après la ligne `claude est sur le PATH` (l. 100) :

```bash
check  "gh est sur le PATH"                      in_base 'command -v gh'
```

Et dans la section « Provisionnement », après la vérification `identity.sh avertit sous root` (l. 185-187) :

```bash
# Sans connexion gh — l'état de tout container tant que l'humain ne s'est pas
# connecté, et de tout container recréé après expiration du jeton. Le
# provisionnement doit continuer, pas s'arrêter là.
check "github-auth sans connexion sort en 0 et dit quoi faire" in_base '
  /usr/local/share/devcontainer/lib/github-auth.sh | grep -q "gh auth login --with-token"'
```

Et dans le bloc `if [ -n "$WEB_IMAGE" ]`, section « Image web », après `java est préinstallé` :

```bash
check "gh traverse la couche web"  in_web 'command -v gh'
```

La couche web repasse `USER root` puis `USER dev`, et `gh` est installé en
user-level : l'héritage se vérifie, il ne se suppose pas — c'est le même
raisonnement que la vérification existante sur `CLAUDE_CONFIG_DIR`.

- [ ] **Step 7: Construire et lancer le smoke test**

Run: `mise run build-base && mise run build-web && mise run test-smoke`
Expected: `gh est sur le PATH` et `github-auth sans connexion sort en 0 et dit quoi faire` en `ok`. Les trois vérifications `post-create` existantes (l. 189-208) restent en `ok` : elles tournent sans connexion `gh`, ce que le script tolère.

- [ ] **Step 8: Commit**

```bash
git add images/agent-base/Dockerfile images/agent-base/lib/github-auth.sh \
        images/agent-base/post-create.sh tests/smoke.sh
git commit -m "gh dans l'image, et la connexion GitHub recâblée à chaque provisionnement"
```

---

## Task 3: Les conventions distribuées

Livrable : un fichier de conventions root-only dans l'image, rattaché au `CLAUDE.md` du volume partagé par une ligne d'import qui ne s'ajoute qu'une fois et n'écrase rien.

**Files:**
- Create: `images/agent-base/etc/conventions.md`
- Create: `images/agent-base/lib/claude-conventions.sh`
- Modify: `images/agent-base/Dockerfile` (bloc `COPY` du provisionnement, l. 100-105)
- Modify: `images/agent-base/post-create.sh`
- Modify: `tests/smoke.sh` (section « Provisionnement »)

**Interfaces:**
- Consomme : `CLAUDE_CONFIG_DIR`, posée par l'image depuis la `1.2.0`, avec repli sur `$HOME/.claude` — même forme que `claude-settings.sh`
- Produit : `/etc/devcontainer/conventions.md` (0444, root) et la ligne `@/etc/devcontainer/conventions.md` dans `$CLAUDE_CONFIG_DIR/CLAUDE.md`

- [ ] **Step 1: Écrire les conventions**

Créer `images/agent-base/etc/conventions.md` :

```markdown
# Conventions de ce container

## Commits

**Aucune mention d'assistant dans les messages de commit** : ni
`Co-Authored-By`, ni `Claude-Session`, ni « Generated with ». L'historique dit
ce que fait le changement, pas avec quel outil il a été écrit.

## Pull requests

**Aucun retour à la ligne manuel à l'intérieur d'un paragraphe.** Un paragraphe
s'écrit sur une seule ligne, aussi longue qu'il le faut, et une ligne vide sépare
deux paragraphes. GitHub rend un saut de ligne simple comme un `<br>` : un texte
replié à 80 colonnes y ressort en lignes courtes et déchiquetées, et le défaut
survit au squash merge, où la description devient le corps du message de commit.

Les listes gardent un élément par ligne : c'est la structure du Markdown, pas un
repli. La règle ne vaut que pour ce que GitHub rend — les fichiers du dépôt
conservent le repli de leur projet.

## Publication

**Ne pousse jamais sur `main`.** Ouvre une branche, pousse-la, ouvre une pull
request. **Ne merge jamais** : l'intégration est un geste humain, fait dans
l'interface.

Ces deux règles sont tenues par la consigne, pas par le container : le jeton
présent ici permettrait de les enfreindre. C'est dit franchement pour que la
confiance porte sur ce qui la mérite.

## Méthode

L'implémentation d'un plan se fait **en subagents**, les tâches indépendantes
étant lancées dans le même message plutôt que l'une après l'autre. Voir la skill
`superpowers:subagent-driven-development`, qui porte le critère d'indépendance.
```

- [ ] **Step 2: Écrire le script de rattachement**

Créer `images/agent-base/lib/claude-conventions.sh` :

```bash
#!/usr/bin/env bash
# Rattache les conventions de l'image au CLAUDE.md du volume partagé.
#
# Une ligne d'import, pas une copie : le contenu vit dans l'image et suit donc
# ses versions, au lieu de se figer au jour où le volume a été créé.
#
# Ajout idempotent et jamais d'écrasement : le volume est partagé entre projets
# et peut porter les mémoires propres de l'utilisateur.
set -uo pipefail

conventions=/etc/devcontainer/conventions.md
[ -f "$conventions" ] || exit 0

config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
memoire="$config/CLAUDE.md"
import="@${conventions}"

mkdir -p "$config"
[ -f "$memoire" ] || : > "$memoire"

if ! grep -qxF "$import" "$memoire"; then
  # Ajouté en tête : ce fichier est de la mémoire utilisateur, on ne veut pas
  # que l'import se retrouve collé à la fin d'un paragraphe écrit à la main.
  printf '%s\n\n%s' "$import" "$(cat "$memoire")" > "$memoire.tmp" \
    && mv "$memoire.tmp" "$memoire"
fi

exit 0
```

- [ ] **Step 3: Écrire les vérifications avant de câbler**

Dans `tests/smoke.sh`, section « Provisionnement », après la vérification `claude-settings préserve les réglages existants` (l. 176-182) :

```bash
# Idempotence sur le nombre d'occurrences, pas sur « au moins une » : ce script
# tourne à chaque recréation sur un volume qui persiste, un ajout aveugle
# empilerait la même ligne indéfiniment.
check "l'import des conventions est ajouté une seule fois" in_base '
  export CLAUDE_CONFIG_DIR=/tmp/cfg-conv
  /usr/local/share/devcontainer/lib/claude-conventions.sh
  /usr/local/share/devcontainer/lib/claude-conventions.sh
  [ "$(grep -cxF "@/etc/devcontainer/conventions.md" $CLAUDE_CONFIG_DIR/CLAUDE.md)" = 1 ]'

# Le volume est partagé : un CLAUDE.md écrit à la main par l'humain ne doit pas
# disparaître au provisionnement suivant.
check "l'import ne détruit pas la mémoire existante" in_base '
  export CLAUDE_CONFIG_DIR=/tmp/cfg-conv2
  mkdir -p $CLAUDE_CONFIG_DIR
  echo "ma memoire a moi" > $CLAUDE_CONFIG_DIR/CLAUDE.md
  /usr/local/share/devcontainer/lib/claude-conventions.sh
  grep -q "ma memoire a moi" $CLAUDE_CONFIG_DIR/CLAUDE.md &&
  grep -qxF "@/etc/devcontainer/conventions.md" $CLAUDE_CONFIG_DIR/CLAUDE.md'

check "les conventions sont en lecture seule pour dev" \
  in_base 'test -r /etc/devcontainer/conventions.md'
refute "dev ne peut pas réécrire les conventions" \
  in_base 'echo compromis > /etc/devcontainer/conventions.md'
```

- [ ] **Step 4: Lancer le smoke test et vérifier que ces quatre lignes échouent**

Run: `mise run build-base && mise run test-smoke`
Expected: trois des quatre nouvelles vérifications en `KO` — ni le fichier ni le script ne sont encore dans l'image. La quatrième, `dev ne peut pas réécrire les conventions`, passe déjà : écrire dans `/etc` échoue pour `dev` que le fichier existe ou non. Elle ne prouvera quelque chose qu'à l'étape suivante, et c'est normal — une vérification de permission n'a de sens que sur un fichier présent.

- [ ] **Step 5: Copier les conventions dans l'image**

Dans `images/agent-base/Dockerfile`, bloc de provisionnement (l. 100-105), ajouter la copie du fichier :

```dockerfile
COPY --chown=root:root --chmod=0555 post-create.sh /usr/local/share/devcontainer/post-create.sh
COPY --chown=root:root --chmod=0555 lib/           /usr/local/share/devcontainer/lib/
COPY --chown=root:root --chmod=0444 etc/plugins.d/ /etc/devcontainer/plugins.d/
COPY --chown=root:root --chmod=0444 etc/conventions.md /etc/devcontainer/conventions.md
RUN chmod 0755 /usr/local/share/devcontainer \
               /usr/local/share/devcontainer/lib \
               /etc/devcontainer/plugins.d
```

`/etc/devcontainer` existe déjà en 0755 depuis la ligne 51 — c'est ce qui rend ce `COPY` sûr sans `chmod` supplémentaire, contrairement aux répertoires que BuildKit crée lui-même.

- [ ] **Step 6: L'appeler depuis le provisionnement**

Dans `images/agent-base/post-create.sh`, après la ligne « Réglages Claude » :

```bash
say "Réglages Claude";     "$lib/claude-settings.sh"
say "Conventions";         "$lib/claude-conventions.sh"
```

- [ ] **Step 7: Reconstruire et vérifier**

Run: `mise run build-base && mise run build-web && mise run test-smoke`
Expected: les quatre vérifications en `ok`, et `post-create est idempotent` (l. 203-208) toujours en `ok` — c'est elle qui exerce le script deux fois de suite dans les conditions réelles.

- [ ] **Step 8: Commit**

```bash
git add images/agent-base/etc/conventions.md images/agent-base/lib/claude-conventions.sh \
        images/agent-base/Dockerfile images/agent-base/post-create.sh tests/smoke.sh
git commit -m "Conventions du container distribuées par l'image et importées dans la mémoire"
```

---

## Task 4: Le montage `agent-gh` dans le template et les invariants

Livrable : le template monte le volume, l'invariant `volumes` l'exige, et les quatre fixtures attendues le portent avec ses commentaires.

**Files:**
- Modify: `plugin/skills/onboard-devcontainer/references/devcontainer.template.json:27-38`
- Modify: `tests/lib/devcontainer-invariants.cjs:20-26` et `:44`
- Modify: `tests/fixtures/onboarding/{brancher,migrer,amorcer,mettre-a-jour}/attendu/devcontainer.json`
- Modify: `plugin/skills/onboard-devcontainer/SKILL.md` (ligne `volumes` de la liste de contrôle)

**Interfaces:**
- Consomme : `/home/dev/.config/gh` créé dans l'image par la Task 2
- Produit : `MONTAGES_PARTAGES['/home/dev/.config/gh'] === 'agent-gh'`, consommé par `verifier()` et par la liste de contrôle de la skill

- [ ] **Step 1: Exiger le montage dans le module d'invariants**

Dans `tests/lib/devcontainer-invariants.cjs`, ajouter l'entrée à `MONTAGES_PARTAGES` (l. 22-26) :

```js
const MONTAGES_PARTAGES = {
  '/home/dev/.claude': 'agent-claude',
  '/home/dev/.config/gh': 'agent-gh',
  '/home/dev/.cache/pnpm-store': 'agent-pnpm-store',
  '/home/dev/.cache/ms-playwright': 'agent-playwright',
};
```

Et corriger le libellé de l'invariant `volumes` (l. 44) :

```js
  { id: 'volumes', libelle: 'les six montages attendus, partagés ou préfixés par le projet' },
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

Run: `mise run test-unit`
Expected: FAIL sur « chaque sortie attendue respecte les invariants » — les quatre fixtures ne portent pas encore le montage, chacune produisant une violation `volumes`.

- [ ] **Step 3: Ajouter le montage au template**

Dans `plugin/skills/onboard-devcontainer/references/devcontainer.template.json`, compléter le commentaire du bloc `mounts` et ajouter la ligne :

```jsonc
  // Les volumes `agent-*` sont volontairement partagés entre projets : login et
  // plugins une seule fois, caches content-addressed où le partage est sûr par
  // construction. Les deux autres sont préfixés par le projet — deux containers
  // ouverts en même temps ne doivent se disputer ni le backend JetBrains ni
  // l'historique de shell.
  //
  // `agent-gh` porte la connexion GitHub. Le montage vise l'emplacement par
  // défaut de gh, ce qui évite toute variable d'environnement — donc tout
  // réglage qu'un IDE pourrait cesser d'honorer en silence.
  "mounts": [
    "source=agent-claude,target=/home/dev/.claude,type=volume",
    "source=agent-gh,target=/home/dev/.config/gh,type=volume",
    "source=<slug>-cache,target=/home/dev/.cache,type=volume",
    "source=agent-pnpm-store,target=/home/dev/.cache/pnpm-store,type=volume",
    "source=agent-playwright,target=/home/dev/.cache/ms-playwright,type=volume",
    "source=<slug>-history,target=/home/dev/.history,type=volume"
  ],
```

- [ ] **Step 4: Reporter dans les quatre fixtures**

Dans chacun des quatre `tests/fixtures/onboarding/*/attendu/devcontainer.json`, ajouter **les trois lignes de commentaire** ci-dessus (après la ligne `// l'historique de shell.`) **et** la ligne de montage `agent-gh`, en deuxième position de `mounts`.

Les commentaires ne sont pas facultatifs : `tests/unit/fixtures-onboarding.test.cjs` vérifie que chaque ligne de commentaire du template figure dans chaque fixture, une assertion par ligne. Le slug diffère d'une fixture à l'autre (`mon-appli`, `compte-de-famille`, …) mais la ligne `agent-gh` est identique partout — c'est un volume partagé.

- [ ] **Step 5: Relancer les tests unitaires**

Run: `mise run test-unit`
Expected: PASS, les deux tests de fixtures compris.

- [ ] **Step 6: Mettre la liste de contrôle de la skill en accord**

Dans `plugin/skills/onboard-devcontainer/SKILL.md`, remplacer la ligne `volumes` de la liste de contrôle finale (l. 103-105) :

```markdown
- `volumes` — les six montages sont là : `agent-claude`, `agent-gh`,
  `agent-pnpm-store` et `agent-playwright` partagés entre projets,
  `<slug>-cache` et `<slug>-history` propres au projet.
```

- [ ] **Step 7: Vérifier l'accord skill ↔ invariants**

Run: `mise run test-unit`
Expected: PASS, `tests/unit/skill-checklist.test.cjs` compris — il vérifie que chaque identifiant d'invariant figure dans `SKILL.md`.

- [ ] **Step 8: Commit**

```bash
git add plugin/skills/onboard-devcontainer/references/devcontainer.template.json \
        plugin/skills/onboard-devcontainer/SKILL.md \
        tests/lib/devcontainer-invariants.cjs tests/fixtures/onboarding
git commit -m "Le template monte le volume de connexion GitHub"
```

---

## Task 5: L'étape credentials de la skill d'onboarding

Livrable : une référence unique qui dit comment créer le PAT, s'y connecter et tenter la ruleset, routée depuis `SKILL.md` et depuis les quatre modes ; et la correction de tous les textes qui affirment encore que `git push` est bloqué.

**Files:**
- Create: `plugin/skills/onboard-devcontainer/references/github.md`
- Modify: `plugin/skills/onboard-devcontainer/SKILL.md` (table de détection et dernier paragraphe)
- Modify: `plugin/skills/onboard-devcontainer/references/brancher.md:114-125`
- Modify: `plugin/skills/onboard-devcontainer/references/amorcer.md` (section « Dire la suite »)
- Modify: `plugin/skills/onboard-devcontainer/references/migrer.md` et `mettre-a-jour.md` (sections « Terminer »)

**Interfaces:**
- Consomme : rien du code
- Produit : `references/github.md`, référencé par les cinq fichiers ci-dessus

- [ ] **Step 1: Écrire la référence**

Créer `plugin/skills/onboard-devcontainer/references/github.md` :

````markdown
# Credentials GitHub

À faire une fois par poste, quel que soit le mode. Le container peut pousser des
branches et ouvrir des pull requests ; il ne merge pas.

## 1. Le jeton

Un **PAT fine-grained**, créé sur github.com, à dépôts sélectionnés :

| Permission | Niveau | Pourquoi |
|---|---|---|
| Contents | lecture/écriture | pousser une branche |
| Pull requests | lecture/écriture | ouvrir et modifier une PR |
| Metadata | lecture | exigée par les deux précédentes |

**Ni `Administration`, ni `Workflows`.** Ce n'est pas une précaution
décorative : sans `Workflows`, GitHub refuse lui-même tout push qui touche
`.github/workflows/`, ce qui est la seule barrière réellement structurelle de ce
dispositif. Sans `Administration`, le jeton ne peut pas défaire la ruleset du §3
ni changer les réglages du dépôt.

Le PAT est partagé par tous les containers, comme le volume de login. Un
container peut donc pousser sur tous les dépôts qu'il couvre : c'est le
prolongement de la portée déjà admise pour `.claude.json`, à dire à l'humain
plutôt qu'à laisser découvrir.

## 2. La connexion

Elle se fait **dans le container**, une fois, à la main :

```bash
gh auth login --with-token
```

puis coller le jeton et Ctrl-D. Le jeton passe par stdin : il n'apparaît dans
aucune ligne de commande, donc pas dans l'historique de shell — qui est
persistant ici. Le volume `agent-gh` garde la connexion d'une recréation à
l'autre ; le provisionnement suivant recâble git tout seul.

Tu ne peux pas la faire à la place de l'humain : le jeton ne doit pas transiter
par une commande que tu composes.

## 3. La ruleset, si GitHub l'accepte

À lancer **depuis le poste**, avec le `gh` de l'humain : créer une ruleset
demande la permission `Administration`, que le PAT du container n'a pas — et ne
doit pas avoir.

Vérifier d'abord ce qui existe, pour ne pas écraser :

```bash
gh api repos/{owner}/{repo}/rulesets --jq '.[].name'
```

Si aucune ne porte ce nom, la créer :

```bash
gh api --method POST repos/{owner}/{repo}/rulesets --input - <<'JSON'
{ "name": "main protégée", "target": "branch", "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [ {"type": "pull_request", "parameters": {"required_approving_review_count": 0}},
             {"type": "deletion"}, {"type": "non_fast_forward"} ] }
JSON
```

`bypass_actors` reste **vide**, y compris du rôle administrateur : le PAT agit au
nom de son propriétaire, donc un bypass accordé à ce rôle serait hérité par le
container et la ruleset ne protégerait plus rien. Conséquence à annoncer :
l'humain non plus ne pousse plus sur `main`, et publie par PR.

Si une ruleset du même nom existe déjà mais diffère, **signale-la sans la
modifier** : elle peut avoir été réglée à la main.

Si GitHub refuse — plan, permission, dépôt privé — dis-le et continue. Ce n'est
pas un prérequis du branchement : c'est un renfort gratuit là où il est
disponible.

## 4. Ce qu'il faut dire à l'humain

Que « pas de push sur `main` » et « pas de merge » sont tenus par le garde-fou et
par les conventions du container, **pas par construction** : le jeton présent
dans la session permettrait de les enfreindre en appelant l'API directement. Les
seules garanties dures sont la portée du PAT et les deux permissions non
accordées.
````

- [ ] **Step 2: Router depuis `SKILL.md`**

Dans `plugin/skills/onboard-devcontainer/SKILL.md`, ajouter un paragraphe après la table de détection du mode (l. 39), avant « Annonce le mode retenu » :

```markdown
Quel que soit le mode, `references/github.md` décrit l'étape credentials : le
jeton à créer, la connexion à faire une fois dans le container, et la ruleset à
tenter depuis le poste. Elle est à traiter à la fin, une fois le
`devcontainer.json` écrit.
```

- [ ] **Step 3: Corriger le dernier paragraphe de `SKILL.md`**

Il affirme encore que la publication est bloquée. Remplacer le paragraphe final (l. 115-119) par :

```markdown
Termine en rappelant à l'humain ce que le garde-fou **ne** protège **pas** : le
jeton d'authentification de l'agent est lisible depuis la session, et celui de
GitHub aussi ; l'agent peut commiter et modifier n'importe quel fichier du
workspace ; le réseau sortant n'est pas filtré ; les règles projet — étant dans
le workspace — sont supprimables. Et surtout : **`main` et le merge ne sont
protégés que par la consigne**. Le garde-fou refuse `git push origin main` et
`gh pr merge`, mais le jeton présent dans la session permettrait de passer par
l'API. Les seules garanties structurelles sont la portée du PAT et les
permissions qu'il n'a pas.
```

- [ ] **Step 4: Corriger le mode « brancher »**

Dans `plugin/skills/onboard-devcontainer/references/brancher.md`, remplacer la section « 4. Terminer » (l. 114-125) :

```markdown
## 4. Terminer

Repasse la liste de contrôle finale de `SKILL.md`, montre les deux fichiers
écrits, et indique la suite : ouvrir le dépôt dans le dev container, puis `yolo`.

Enchaîne sur `references/github.md` : sans la connexion décrite là, le container
ne peut ni pousser ni ouvrir de PR.

Dis-lui aussi que **le workspace vivra dans un volume Docker et pas sur son
disque**, et qu'il **ne survit pas à la recréation du container** : JetBrains
re-clone depuis le distant dans un volume de sources neuf, donc ce qui n'a pas
été poussé disparaît — commits locaux compris, et sur un rebuild réussi, pas
seulement sur un accident. Pousser une branche est désormais possible depuis le
container, et c'est la seule chose qui met le travail à l'abri.
```

- [ ] **Step 5: Corriger le mode « amorcer »**

Dans `plugin/skills/onboard-devcontainer/references/amorcer.md`, section « Dire la suite, dans l'ordre », remplacer le paragraphe qui commence par « Dis-lui enfin que **le projet qui va naître** » par :

```markdown
Dis-lui enfin que **le projet qui va naître dans ce container vivra dans un
volume Docker et pas sur son disque**, et qu'il ne survit pas à la recréation du
container. C'est plus aigu ici que dans les autres modes : le dépôt est vide,
donc il n'existe aucune copie ailleurs tant que rien n'a été poussé. Enchaîne sur
`references/github.md` — c'est ce qui rend le premier push possible.
```

- [ ] **Step 6: Renvoyer depuis les deux autres modes**

Dans `references/migrer.md` et `references/mettre-a-jour.md`, ajouter en fin de la section « Terminer » :

```markdown
Enchaîne sur `references/github.md` : le montage `agent-gh` ne sert à rien tant
que la connexion `gh` n'a pas été faite une fois dans le container.
```

- [ ] **Step 7: Vérifier que la skill reste cohérente**

Run: `mise run test-unit`
Expected: PASS. `skill-checklist.test.cjs` vérifie les identifiants d'invariants et l'existence d'un fichier de référence par mode ; `github.md` n'est pas un mode, il n'a donc rien à y ajouter. S'il échoue, c'est qu'un identifiant d'invariant a été perdu en réécrivant la liste de contrôle.

- [ ] **Step 8: Commit**

```bash
git add plugin/skills/onboard-devcontainer
git commit -m "L'onboarding pose les credentials GitHub et tente la ruleset"
```

---

## Task 6: Le README

Livrable : le principe affiché du dépôt est à jour, une section explique comment pousser, et les limites disent franchement ce qui n'est pas protégé.

**Files:**
- Modify: `README.md:9-13` (le principe), après la section « Règles de garde-fou propres à un projet » (nouvelle section), `:164-183` (« Publier une version »), `:192-221` (les limites), `:204-215` (le workspace)

**Interfaces:**
- Consomme : rien
- Produit : rien que d'autres tâches consomment

- [ ] **Step 1: Corriger le principe affiché**

Remplacer le paragraphe d'introduction (l. 9-13) :

```markdown
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
```

- [ ] **Step 2: Écrire la section « Pousser et ouvrir des PR »**

L'insérer entre « Règles de garde-fou propres à un projet » et « Ce qui persiste d'une recréation à l'autre » :

````markdown
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
````

- [ ] **Step 3: Mettre à jour les limites du garde-fou**

Dans la section « Ce que le garde-fou ne protège pas », remplacer la deuxième puce et en ajouter une :

```markdown
- **L'agent peut commiter localement et modifier n'importe quel fichier du
  workspace.** Il peut aussi pousser une branche et ouvrir une PR. Restent
  bloqués : `firebase deploy`, `npm publish`, tout `gcloud`, et les commandes
  `gh` hors création/modification/lecture de PR.
- **`main` et le merge ne sont protégés que par la consigne.** Le garde-fou
  refuse `git push origin main` et `gh pr merge`, mais le jeton GitHub est
  lisible depuis la session et l'API est joignable : un appel direct passerait.
  C'est un choix, pas un oubli — les garanties dures sont la portée du PAT et les
  permissions qu'il n'a pas. Une ruleset sur `main` referme le premier point là
  où GitHub l'accepte ; l'onboarding la tente.
- **Le volume `agent-gh` est partagé entre projets**, donc tout container peut
  pousser sur tous les dépôts que le PAT couvre. Même portée que `.claude.json`,
  déjà partagé.
```

- [ ] **Step 4: Adoucir la puce sur le workspace**

Dans la même section, la dernière puce affirme que la fenêtre de perte est longue *parce que* `git push` est bloqué. Remplacer sa dernière phrase :

```markdown
  La fenêtre s'est refermée depuis que le container peut pousser : c'est
  maintenant à portée de l'agent, et une branche poussée est la seule copie qui
  survit au volume.
```

- [ ] **Step 5: Corriger la procédure de publication**

La section « Publier une version » donne `git push origin main --tags`. Si une
ruleset est posée sur le `main` de ce dépôt-ci, cette commande cesse de
fonctionner — et de toute façon le dépôt s'applique désormais ses propres
règles. Remplacer le bloc de commandes de fin de section par :

````markdown
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
````

- [ ] **Step 6: Vérifier qu'aucune affirmation contradictoire ne subsiste**

Run: `grep -n "git push" README.md plugin/skills/onboard-devcontainer/*.md plugin/skills/onboard-devcontainer/references/*.md images/agent-base/post-create.sh`
Expected: aucune occurrence n'affirme plus que `git push` est bloqué en bloc. Les seules mentions restantes disent « bloqué sur `main` » ou décrivent la liste blanche.

- [ ] **Step 7: Commit**

```bash
git add README.md
git commit -m "Le README dit ce que le jeton GitHub permet, et ce qu'il ne protège pas"
```

---

## Task 7: Publier la `1.3.0`

Livrable : les manifestes portent la version, la CI reconstruit, rejoue les tests contre les images construites et publie.

**Files:**
- Modify: `plugin/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

**Interfaces:**
- Consomme : tout ce qui précède
- Produit : les images `ghcr.io/charlouze/devcontainer-agent-base:1.3.0` et `…-web:1.3.0`, et le déplacement du tag flottant `1`

- [ ] **Step 1: Porter la version dans les deux manifestes**

`plugin/.claude-plugin/plugin.json` : `"version": "1.3.0"`.
`.claude-plugin/marketplace.json` : la même valeur dans l'unique entrée de `plugins`.

Le template n'est **pas** touché : il reste sur `ghcr.io/charlouze/devcontainer-web:1`. Un projet déjà branché continue de fonctionner sans le montage `agent-gh` — il perd seulement la persistance de la connexion, qu'il n'avait pas avant.

- [ ] **Step 2: Vérifier la cohérence des manifestes**

Run: `mise run test-unit`
Expected: PASS, `tests/unit/plugin-manifests.test.cjs` compris.

- [ ] **Step 3: Rejouer la séquence complète de la CI**

Run: `mise run check`
Expected: aucune vérification en échec.

- [ ] **Step 4: Commit**

```bash
git add plugin/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "Version 1.3.0"
```

- [ ] **Step 5: Ouvrir la pull request**

Le dépôt s'applique ses propres règles : branche, PR, merge dans l'interface. Le corps de la PR s'écrit en paragraphes d'une seule ligne — GitHub rend un saut de ligne simple comme un `<br>`, et la description devient le corps du message de commit au squash merge.

Le corps reprend le §1 et le §2 de la spec : ce que la branche apporte, et le
déplacement assumé de la garantie — un jeton entre dans le container, `main` et
le merge ne tiennent plus que par la consigne. Chaque paragraphe sur une ligne.

```bash
git push -u origin <branche>
gh pr create --title "Pousser et ouvrir des PR depuis le container" --body-file <fichier>
```

`--body-file` plutôt que `--body` : un corps de plusieurs paragraphes passé en
argument se fait replier par le shell, ce que la convention interdit précisément.

- [ ] **Step 6: Taguer après le merge**

L'ordre compte : `main` doit porter la marketplace en `1.3.0` avant que le tag n'existe, sinon chaque container qui provisionne avertit sur un plugin introuvable.

```bash
git checkout main && git pull
git tag v1.3.0 && git push origin v1.3.0
```

- [ ] **Step 7: Vérifier la publication**

Run: `gh run watch`
Expected: le workflow en succès, et `ghcr.io/charlouze/devcontainer-agent-base:1.3.0` disponible. Un échec n'atteint jamais le tag flottant `1`.

---

## Points à vérifier pendant l'exécution

1. **`mise use --global --yes gh@latest` résout-il vraiment ?** C'est le seul pari de ce plan sur un outillage extérieur. Le repli apt est écrit en Task 2 Step 3 ; ce qui n'est pas acceptable, c'est un `gh` absent qui ne se manifeste qu'à la première tentative de PR. Le smoke test `gh est sur le PATH` est là pour ça.

2. **Le lookbehind de la règle `git push` est-il supporté ?** V8 accepte le lookbehind de longueur variable, mais l'interprète du garde-fou est le `nodejs` du dépôt Debian, pas celui de mise. À vérifier explicitement dans l'image plutôt qu'à supposer depuis le poste :

   ```bash
   docker run --rm -u dev devcontainer-agent-base:dev \
     /usr/local/lib/claude-guard/node -e 'console.log(/(?<=[\s:]|refs\/heads\/)main/.test("git push origin main"))'
   ```

   Attendu : `true`. Si l'interprète est trop ancien, il jette à la compilation — donc le garde-fou tomberait *en entier*, et le smoke test le verrait sur toutes ses vérifications d'un coup.

3. **`gh auth setup-git` écrit-il là où git le relira ?** Il pose un `credential.helper` dans `~/.gitconfig`, hors volume, donc reposé à chaque provisionnement. Après la première connexion réelle, le vérifier :

   ```bash
   git config --global --get-regexp credential
   git ls-remote https://github.com/<owner>/<dépôt> >/dev/null && echo ok
   ```

4. **L'import des conventions est-il réellement lu par Claude Code ?** Le smoke test prouve que la ligne est écrite au bon endroit, pas qu'elle est honorée — la mémoire utilisateur demande une session. Après le premier rebuild, ouvrir une session et demander à l'agent de citer les conventions du container. Si elles sont absentes, vérifier que `CLAUDE_CONFIG_DIR` et le fichier `CLAUDE.md` désignent bien le même répertoire.

5. **Le premier `gh auth login` doit tenir après recréation.** C'est le point de tout le design : se connecter, recréer le container, et vérifier que `gh auth status` répond sans reconnexion. Si la connexion est perdue, le montage `agent-gh` ne vise pas l'emplacement que `gh` utilise réellement — vérifier avec `gh auth status` puis `ls -la /home/dev/.config/gh`.

6. **Le garde-fou refuse-t-il toujours ce qu'il refusait ?** Ce plan réécrit deux règles du socle et n'en touche aucune autre. Après reconstruction, exercer depuis une session : `firebase deploy` (bloqué), `gcloud auth list` (bloqué), la lecture d'un `.env` (bloquée). Le smoke test les couvre, mais elles n'ont jamais été exercées à travers `claude` lui-même.

## Suite

Rien de ce plan ne laisse de dette ouverte, hors les six limites assumées de la spec §10. La question qui se reposera est celle du **merge structurellement humain** : elle ne se règle qu'avec une identité distincte pour le container (compte machine ou GitHub App, spec §3), et cette conception a été écartée pour son coût, pas parce qu'elle serait mauvaise. Le jour où un dépôt cesse d'être personnel, c'est là qu'il faut revenir.
