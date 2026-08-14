# Persistance de l'état de Claude Code — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Faire survivre l'état de Claude Code — onboarding, identité de compte, confiance du projet — à la recréation d'un container, en posant `CLAUDE_CONFIG_DIR` dans l'image de base plutôt que dans le template.

**Architecture:** Une seule ligne `ENV` porte le correctif ; tout le reste du plan sert à empêcher qu'elle dérive ou qu'elle mente. Un test unitaire tient la valeur en accord avec la cible du montage `agent-claude` qu'épingle déjà le module d'invariants, le smoke test vérifie qu'elle est exportée à tout processus — y compris sans shell, ce qui est exactement ce qu'un `containerEnv` ne garantit pas — et une sonde manuelle tranche, avant que le README n'affirme quoi que ce soit, ce que l'écriture concurrente coûte réellement sur un volume de login partagé.

**Tech Stack:** Dockerfile, bash, Node.js `node:test`, jq, Docker, mise, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-14-persistance-etat-claude-design.md`

**Plans précédents:** `2026-08-14-devcontainer-images.md` et `2026-08-14-plugin-onboarding.md`, tous deux exécutés et publiés (`v1.0.0`, `v1.1.0`). Ce plan-ci ne reprend aucune de leurs dettes.

## Global Constraints

- **Langue.** Commentaires, messages, contenu des skills et sorties utilisateur en **français**. Convention du dépôt, elle prime sur l'usage anglophone de l'écosystème.
- **Fins de ligne.** LF partout (`.gitattributes` en place).
- **Messages de commit** : en français, descriptifs, sans préfixe conventionnel (`feat:`, `docs:`, …) — c'est l'usage du dépôt. **Aucune mention d'assistant** : ni `Co-Authored-By`, ni `Claude-Session`, ni « Generated with ».
- **La valeur du chemin est `/home/dev/.claude`**, à l'octet près, partout où elle apparaît : `images/agent-base/Dockerfile`, `MONTAGES_PARTAGES` dans `tests/lib/devcontainer-invariants.cjs:23`, et le montage `agent-claude` du template. Deux chaînes qui divergent scindent l'état entre deux racines dont une seule est dans le volume, sans la moindre erreur.
- **Version du plugin = version des images = `1.2.0`.** À porter dans `plugin/.claude-plugin/plugin.json` et `.claude-plugin/marketplace.json`. Le template reste sur le tag `:1` : ce n'est pas un changement de majeure.
- **Le socle du garde-fou n'est pas touché** par ce plan. Aucun fichier sous `/etc/claude-*` ni `/usr/local/lib/claude-guard/` n'est modifié.
- **Sous Windows, tout ce qui touche Docker se lance depuis Git Bash.** Dans PowerShell, `bash` résout vers le lanceur WSL et échoue.

---

## Structure des fichiers

| Fichier | Responsabilité | Statut |
|---|---|---|
| `images/agent-base/Dockerfile` | Porte `ENV CLAUDE_CONFIG_DIR` | Modifié |
| `images/agent-base/lib/claude-settings.sh` | Suit la variable au lieu de recalculer le chemin | Modifié |
| `tests/lib/devcontainer-invariants.cjs` | Exporte `MONTAGES_PARTAGES` pour que l'image puisse s'y accorder | Modifié |
| `tests/unit/image-config-dir.test.cjs` | Accord image ↔ template sur la valeur du chemin | Créé |
| `tests/smoke.sh` | Export à tout processus, persistance, suivi de la variable par le script | Modifié |
| `README.md` | Ce qui persiste, ce qui ne persiste pas, et pourquoi le volume est la seule copie | Modifié |
| `plugin/skills/onboard-devcontainer/references/brancher.md` | Avertissement « le volume est la seule copie » | Modifié |
| `plugin/skills/onboard-devcontainer/references/amorcer.md` | Idem | Modifié |
| `plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | Version `1.2.0` | Modifiés |

**Note de décomposition — pourquoi la sonde est une tâche et non une note.** La Task 1 ne produit aucun code. Elle existe parce que la §4 de la spec repose sur une hypothèse non mesurée (Claude Code réécrit-il `.claude.json` intégralement, ou fusionne-t-il avec le disque ?), et que la réponse change ce que la Task 3 écrit dans le README. Documenter une garantie qu'on n'a pas vérifiée est précisément le genre de fausse assurance que ce dépôt refuse ailleurs — le garde-fou a sa section « ce qu'il ne protège pas » pour la même raison.

**Ordre d'exécution.** Task 1 avant Task 3. La Task 2 est indépendante des deux et peut passer en premier si la sonde demande d'attendre une occasion.

---

## Task 1: Sonde — que coûte réellement l'écriture concurrente

Aucun livrable de code. Le livrable est une réponse, consignée dans ce fichier, qui détermine la formulation de la Task 3.

**Files:**
- Modify: `docs/superpowers/plans/2026-08-14-persistance-etat-claude.md` (consigner le verdict dans cette tâche)

**Interfaces:**
- Consomme : rien
- Produit : le verdict `réécriture intégrale` ou `fusion`, que la Task 3 Step 2 cite

**Prérequis :** un container existant, avec une session Claude Code authentifiée. N'importe quel projet déjà branché convient — la sonde porte sur le comportement de Claude Code, pas sur l'image nouvelle.

- [ ] **Step 1: Sauvegarder la configuration avant de la manipuler**

Le fichier porte l'identité du compte et il est en mode 600 ; `-p` conserve les deux.

```bash
cp -p ~/.claude.json ~/.claude.json.sonde-backup
ls -l ~/.claude.json.sonde-backup
```

Expected: un fichier en `-rw-------`, taille non nulle.

- [ ] **Step 2: Ouvrir une session Claude Code et la laisser en cours**

Dans un premier terminal :

```bash
claude
```

Laisser la session ouverte : c'est elle qui tient l'instantané en mémoire dont on veut savoir s'il écrase le disque. Ne rien lui demander, aucun jeton n'a besoin d'être dépensé.

- [ ] **Step 3: Injecter un marqueur depuis un second terminal**

Dans un second terminal du **même** container, pendant que la session tourne :

```bash
jq '.sondeMarqueur = "temoin"' ~/.claude.json > /tmp/sonde.json && mv /tmp/sonde.json ~/.claude.json
grep -c sondeMarqueur ~/.claude.json
```

Expected: `1`. Le marqueur joue le rôle de ce qu'un second container aurait écrit.

- [ ] **Step 4: Provoquer une écriture par la session, puis la terminer**

Dans le premier terminal, quitter la session (`/exit`). La fin de session écrit l'historique de prompts du projet, donc le fichier.

- [ ] **Step 5: Lire le verdict**

```bash
grep -c sondeMarqueur ~/.claude.json
```

- `0` → **réécriture intégrale** depuis l'instantané en mémoire. L'hypothèse de la spec §4 est confirmée : un second container peut faire régresser les clés `projects[<chemin>]` de l'autre. Les clés globales convergent quand même, les deux containers y écrivant la même valeur.
- `1` → **fusion** avec l'état sur disque. La concurrence est bénigne, et la §4 de la spec est trop prudente : la Task 3 le dit alors sans réserve.

- [ ] **Step 6: Restaurer**

```bash
cp -p ~/.claude.json.sonde-backup ~/.claude.json
rm ~/.claude.json.sonde-backup
```

Attention : cette restauration ramène l'état d'avant la sonde et perd donc ce que la session du Step 2 a écrit entre-temps. C'est sans conséquence ici (aucun prompt n'a été soumis) ; ne pas la rejouer telle quelle après une vraie session de travail.

- [ ] **Step 7: Consigner le verdict dans ce fichier**

Remplacer la ligne ci-dessous par le résultat, date comprise, puis committer.

> **Verdict de la sonde :** _(à remplir — `réécriture intégrale` ou `fusion`, et la date)_

```bash
git add docs/superpowers/plans/2026-08-14-persistance-etat-claude.md
git commit -m "Verdict de la sonde d'écriture concurrente sur .claude.json"
```

**Si la sonde ne peut pas être menée** (pas de container authentifié sous la main), ne pas bloquer le plan : la Task 3 s'en tient alors à ce qui est observable sans elle — les clés globales convergent, le suivi par projet peut régresser — et la formulation reste au conditionnel. Le noter ici plutôt que de laisser croire que la question a été tranchée.

---

## Task 2: La variable dans l'image, et ce qui l'empêche de dériver

Livrable : l'image exporte `CLAUDE_CONFIG_DIR`, la valeur ne peut plus diverger de celle du template sans faire échouer un test, et `claude-settings.sh` suit la variable au lieu de recalculer le chemin.

**Files:**
- Modify: `tests/lib/devcontainer-invariants.cjs` (ligne finale `module.exports`)
- Create: `tests/unit/image-config-dir.test.cjs`
- Modify: `images/agent-base/Dockerfile` (après la ligne `ENV PATH=…`, l. 64)
- Modify: `images/agent-base/lib/claude-settings.sh`
- Modify: `tests/smoke.sh` (nouvelle section, avant `section "Provisionnement"`)

**Interfaces:**
- Consomme : `MONTAGES_PARTAGES` de `tests/lib/devcontainer-invariants.cjs`, aujourd'hui interne au module
- Produit :
  - `MONTAGES_PARTAGES` exporté, objet `{ [cible: string]: source: string }`, dont `'/home/dev/.claude': 'agent-claude'`
  - `ENV CLAUDE_CONFIG_DIR=/home/dev/.claude` dans l'image `agent-base`, donc héritée par l'image `web`

- [ ] **Step 1: Exporter `MONTAGES_PARTAGES`**

Le module épingle déjà la cible du montage de login, mais ne la publie pas. Le test qui suit en a besoin comme source de vérité — la dupliquer ferait exactement la dérive qu'on veut interdire.

Dans `tests/lib/devcontainer-invariants.cjs`, dernière ligne :

```js
module.exports = { verifier, INVARIANTS, IMAGE, POST_CREATE, MONTAGES_PARTAGES };
```

- [ ] **Step 2: Écrire le test d'accord image ↔ template**

Créer `tests/unit/image-config-dir.test.cjs` :

```js
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const { MONTAGES_PARTAGES } = require('../lib/devcontainer-invariants.cjs');

const racine = path.join(__dirname, '../..');
const dockerfile = fs.readFileSync(path.join(racine, 'images/agent-base/Dockerfile'), 'utf8');

// Claude Code range son fichier de configuration principal à côté du répertoire
// `.claude`, pas dedans. Sans cette variable il reste hors du volume et meurt
// avec le container.
test("l'image de base exporte CLAUDE_CONFIG_DIR", () => {
  assert.match(dockerfile, /^ENV CLAUDE_CONFIG_DIR=\S+$/m);
});

// Le cœur du test : la valeur et la cible du montage `agent-claude` doivent
// rester la même chaîne. Si elles divergent, l'état se scinde entre deux racines
// dont une seule est persistée, et rien ne le signale à l'exécution.
test('la valeur est la cible du montage de login partagé', () => {
  const [, valeur] = dockerfile.match(/^ENV CLAUDE_CONFIG_DIR=(\S+)$/m);
  assert.strictEqual(
    MONTAGES_PARTAGES[valeur],
    'agent-claude',
    `${valeur} n'est pas la cible du montage agent-claude`
  );
});
```

- [ ] **Step 3: Lancer le test et vérifier qu'il échoue**

Run: `mise run test-unit`
Expected: FAIL sur `l'image de base exporte CLAUDE_CONFIG_DIR`, le Dockerfile ne portant pas encore la ligne. Le second test échoue aussi, sur un `match` qui rend `null`.

- [ ] **Step 4: Poser la variable dans le Dockerfile**

Dans `images/agent-base/Dockerfile`, juste après la ligne `ENV PATH=…` (l. 64), avant l'installation de mise :

```dockerfile
# Claude Code range son état dans le répertoire `.claude`, mais son fichier de
# configuration principal est `~/.claude.json` — un FRÈRE du répertoire, pas un
# enfant. Sans cette variable il reste hors du volume et meurt avec le
# container : onboarding rejoué, dialogue de confiance reposé, et connexion
# redemandée malgré un jeton pourtant persisté — l'identité vit dans ce fichier
# (`oauthAccount`), pas dans les credentials.
#
# Ici et non dans `containerEnv` du template : un `containerEnv` que l'IDE
# cesserait d'honorer revient vide, Claude Code retombe sur $HOME, et les
# réglages se remettent à mourir à chaque rebuild sans erreur nulle part. Un ENV
# d'image ne peut pas être ignoré, et il est atteignable par le smoke test.
#
# La valeur doit rester identique à la cible du montage `agent-claude` du
# template ; tests/unit/image-config-dir.test.cjs tient les deux en accord.
ENV CLAUDE_CONFIG_DIR=/home/dev/.claude
```

- [ ] **Step 5: Relancer le test unitaire**

Run: `mise run test-unit`
Expected: PASS, les deux tests compris.

- [ ] **Step 6: Faire suivre la variable par `claude-settings.sh`**

Le script vise aujourd'hui `$HOME/.claude` en dur. Les deux chemins coïncident, et c'est justement pourquoi la dérive future passerait inaperçue.

Dans `images/agent-base/lib/claude-settings.sh`, remplacer :

```bash
settings="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
```

par :

```bash
# Le repli garde le script utilisable hors de l'image, où la variable n'est pas
# posée. Dans l'image, les deux valeurs coïncident — le point est qu'elles ne
# puissent pas diverger si le chemin change un jour d'un seul côté.
config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$config/settings.json"
mkdir -p "$config"
```

- [ ] **Step 7: Écrire les vérifications au niveau container**

Dans `tests/smoke.sh`, insérer cette section juste avant `section "Provisionnement"` (l. 118) :

```bash
section "État de Claude Code"

# Sans shell du tout, donc sans /etc/profile ni fichier rc : c'est ce qu'un ENV
# d'image garantit et qu'un containerEnv ne garantit pas. Le lifecycle script,
# le terminal de l'IDE et un `docker exec` la voient tous les trois.
check "CLAUDE_CONFIG_DIR est exportée à tout processus" \
  test "$(docker run --rm -u dev "${HARD[@]}" "$BASE_IMAGE" printenv CLAUDE_CONFIG_DIR)" = /home/dev/.claude

# /etc/profile réécrit PATH de zéro — d'où le rattrapage documenté dans le
# Dockerfile. On vérifie que la variable, elle, traverse bien un shell de login.
check "CLAUDE_CONFIG_DIR survit au shell de login" \
  test "$(in_base 'printf %s "$CLAUDE_CONFIG_DIR"')" = /home/dev/.claude

# Le témoin est écrit À TRAVERS la variable, jamais à un chemin en dur : le test
# échoue donc dès que la variable et le montage cessent de désigner le même
# endroit. Ce qu'il prouve est la plomberie — que Claude Code écrive réellement
# là relève d'une vérification manuelle, elle demande une session authentifiée.
CFG_VOL="smoke-claude-$$"
check "un fichier écrit dans CLAUDE_CONFIG_DIR survit à la recréation" bash -c '
  docker run --rm -u dev -v '"$CFG_VOL"':/home/dev/.claude '"$BASE_IMAGE"' \
    bash -lc "echo temoin > \$CLAUDE_CONFIG_DIR/.claude.json" &&
  docker run --rm -u dev -v '"$CFG_VOL"':/home/dev/.claude '"$BASE_IMAGE"' \
    bash -lc "grep -q temoin \$CLAUDE_CONFIG_DIR/.claude.json"'
docker volume rm "$CFG_VOL" >/dev/null 2>&1 || true

# Valeur détournée, et pas la valeur par défaut : avec celle-ci, un script resté
# en dur sur $HOME/.claude passerait le test sans suivre la variable.
check "claude-settings.sh suit CLAUDE_CONFIG_DIR" in_base '
  CLAUDE_CONFIG_DIR=/tmp/cfg /usr/local/share/devcontainer/lib/claude-settings.sh
  [ "$(jq -r .skipDangerousModePermissionPrompt /tmp/cfg/settings.json)" = true ]'
```

- [ ] **Step 8: Construire les images et lancer le smoke test**

Run: `mise run build-base && mise run build-web && mise run test-smoke`
Expected: les quatre nouvelles vérifications en `ok`, et les deux vérifications existantes de `claude-settings` (l. 141-151) toujours en `ok` — elles visent `~/.claude`, que la variable désigne désormais explicitement.

- [ ] **Step 9: Rejouer la séquence complète de la CI**

Run: `mise run check`
Expected: aucune vérification en échec.

- [ ] **Step 10: Commit**

```bash
git add tests/lib/devcontainer-invariants.cjs tests/unit/image-config-dir.test.cjs \
        images/agent-base/Dockerfile images/agent-base/lib/claude-settings.sh tests/smoke.sh
git commit -m "L'état de Claude Code persiste : CLAUDE_CONFIG_DIR posée dans l'image"
```

---

## Task 3: Documenter ce qui persiste, et ce que le partage coûte

Livrable : une section de README qui explique le défaut corrigé, ce que le premier rebuild va faire, et ce que le volume de login partagé implique quand deux containers tournent.

**Files:**
- Modify: `README.md` (nouvelle section, après « Règles de garde-fou propres à un projet »)

**Interfaces:**
- Consomme : le verdict de la Task 1 Step 7
- Produit : rien que d'autres tâches consomment

- [ ] **Step 1: Écrire la section**

Insérer dans `README.md`, entre la section « Règles de garde-fou propres à un projet » et « Publier une version » :

````markdown
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

**Le volume de login est partagé entre projets**, à dessein. Deux containers
ouverts en même temps écrivent donc le même fichier. Les clés qui comptent —
`hasCompletedOnboarding`, `oauthAccount` — sont globales et reçoivent la même
valeur des deux côtés : elles convergent. Ce qui peut régresser est le suivi par
projet, et le symptôme est un dialogue de confiance qui réapparaît une fois. En
mode YOLO, `allowedTools` n'a de toute façon aucun effet.

**Une configuration corrompue survit désormais aussi.** Ce fichier se corrompt en
pratique ; jusqu'ici la couche inscriptible l'effaçait au rebuild suivant, par
accident. Si un container reconstruit repart sur un onboarding vierge, regarder
`~/.claude/backups/` avant de se reconnecter : Claude Code y tient des copies
`.claude.json.backup.*`, et y met en quarantaine ce qu'il n'a pas su relire.
````

- [ ] **Step 2: Accorder la formulation au verdict de la sonde**

Reprendre le paragraphe « Le volume de login est partagé entre projets » :

- verdict **réécriture intégrale** → le texte ci-dessus convient tel quel ;
- verdict **fusion** → remplacer les deux dernières phrases par : « Claude Code fusionne ses écritures avec l'état trouvé sur disque (vérifié le _(date)_), la concurrence est donc sans effet observable. » ;
- **sonde non menée** → ajouter en fin de paragraphe : « Ce partage n'a pas été éprouvé avec deux containers actifs simultanément. »

- [ ] **Step 3: Vérifier que rien d'autre du README ne contredit la nouvelle section**

Run: `grep -n "credentials\|persist\|volume" README.md`
Expected: la section « Ce que le garde-fou ne protège pas » mentionne toujours que le jeton d'authentification est lisible depuis la session — c'est cohérent, et à laisser tel quel. Aucune autre affirmation sur ce qui survit à un rebuild ne doit subsister ailleurs.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Documente ce qui persiste d'une recréation à l'autre"
```

---

## Task 4: L'avertissement qui manquait — le volume est la seule copie

Livrable : le README et les deux modes de la skill qui créent un container disent que le travail non poussé ne vit qu'à un seul endroit.

**Files:**
- Modify: `README.md` (section « Ce que le garde-fou ne protège pas »)
- Modify: `plugin/skills/onboard-devcontainer/references/brancher.md`
- Modify: `plugin/skills/onboard-devcontainer/references/amorcer.md`

**Interfaces:**
- Consomme : rien
- Produit : rien que d'autres tâches consomment

- [ ] **Step 1: Ajouter le point au README**

Dans `README.md`, section « Ce que le garde-fou ne protège pas », ajouter en fin de liste :

```markdown
- **Le workspace ne vit que dans un volume Docker**, pas sur le disque de
  l'hôte. Un `docker volume prune`, une remise à zéro de Docker Desktop ou un
  volume orphelin après un rebuild raté emporte le travail non poussé, et aucune
  sauvegarde de l'hôte ne le couvre. La fenêtre est plus longue ici qu'ailleurs :
  le garde-fou bloque `git push`, donc c'est l'humain qui publie, et rien ne le
  fait à sa place.
```

- [ ] **Step 2: Ajouter l'avertissement au mode « brancher »**

Dans `plugin/skills/onboard-devcontainer/references/brancher.md`, section « 4. Terminer » (l. 114-117), à la suite de la phrase existante. La section entière devient :

```markdown
## 4. Terminer

Repasse la liste de contrôle finale de `SKILL.md`, montre les deux fichiers
écrits, et indique la suite : ouvrir le dépôt dans le dev container, puis `yolo`.

Dis-lui aussi que **le workspace vivra dans un volume Docker et pas sur son
disque** : le garde-fou bloque `git push`, c'est donc lui qui publie, et un
volume perdu emporte tout ce qui ne l'a pas été.
```

- [ ] **Step 3: Ajouter le même avertissement au mode « amorcer »**

Dans `plugin/skills/onboard-devcontainer/references/amorcer.md`, section « 4. Dire la suite, dans l'ordre », en dernier paragraphe — après « Ne génère pas l'application toi-même… » (l. 62) et avant le titre de la section 5 :

```markdown
Dis-lui enfin que **le projet qui va naître dans ce container vivra dans un
volume Docker et pas sur son disque**. C'est plus aigu ici que dans les autres
modes : le dépôt est vide, donc il n'existe aucune copie ailleurs tant que rien
n'a été poussé — et le garde-fou bloque `git push`.
```

- [ ] **Step 4: Vérifier que la liste de contrôle de la skill reste en accord**

Run: `mise run test-unit`
Expected: PASS. `tests/unit/skill-checklist.test.cjs` tient les invariants mécaniques et la liste de contrôle en accord ; ces ajouts sont de la prose adressée à l'humain et n'introduisent pas d'invariant, donc le test doit passer sans modification. S'il échoue, c'est que la formulation a été placée dans la liste de contrôle plutôt que dans le compte rendu : la déplacer.

- [ ] **Step 5: Commit**

```bash
git add README.md plugin/skills/onboard-devcontainer/references/brancher.md \
        plugin/skills/onboard-devcontainer/references/amorcer.md
git commit -m "Avertit que le workspace ne vit que dans un volume Docker"
```

---

## Task 5: Publier la `1.2.0`

Livrable : les manifestes portent la version, la CI reconstruit, rejoue les tests contre les images construites et publie.

**Files:**
- Modify: `plugin/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

**Interfaces:**
- Consomme : tout ce qui précède
- Produit : les images `ghcr.io/charlouze/devcontainer-agent-base:1.2.0` et `…-web:1.2.0`, et le déplacement du tag flottant `1`

- [ ] **Step 1: Porter la version dans les deux manifestes**

`plugin/.claude-plugin/plugin.json` : `"version": "1.2.0"`.
`.claude-plugin/marketplace.json` : la même valeur dans l'unique entrée de `plugins`.

Le template n'est **pas** touché : il reste sur `ghcr.io/charlouze/devcontainer-web:1`. La règle du README sur le tag du template ne vaut que pour un changement de majeure.

- [ ] **Step 2: Vérifier la cohérence des manifestes**

Run: `mise run test-unit`
Expected: PASS, `tests/unit/plugin-manifests.test.cjs` compris — c'est lui qui vérifie que marketplace, plugin et tag du template s'accordent.

- [ ] **Step 3: Rejouer la séquence complète**

Run: `mise run check`
Expected: aucune vérification en échec.

- [ ] **Step 4: Commit**

```bash
git add plugin/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "Version 1.2.0"
```

- [ ] **Step 5: Taguer et pousser**

L'ordre compte : `main` doit porter la marketplace en `1.2.0` avant que le tag n'existe, sinon chaque container qui provisionne avertit sur un plugin introuvable. La forme ci-dessous pousse les deux ensemble.

```bash
git tag v1.2.0
git push origin main --tags
```

- [ ] **Step 6: Vérifier la publication**

Le workflow construit les deux images, rejoue les tests unitaires **et le smoke test contre les images construites**, puis publie. Un échec n'atteint jamais le tag flottant `1`.

Run: `gh run watch`
Expected: le workflow en succès, et `ghcr.io/charlouze/devcontainer-agent-base:1.2.0` disponible.

---

## Points à vérifier pendant l'exécution

1. **Claude Code honore-t-il réellement `CLAUDE_CONFIG_DIR` ?** Le smoke test prouve la plomberie — variable exportée, volume monté, fichier persistant — pas le comportement de l'agent. La preuve demande une session authentifiée, donc hors CI. Après le premier rebuild sur la `1.2.0`, dans le container :

   ```bash
   echo "$CLAUDE_CONFIG_DIR"          # /home/dev/.claude
   ls -l "$CLAUDE_CONFIG_DIR/.claude.json"
   claude auth status
   ```

   La vérification qui tranche est la dernière : `email` et `orgName` doivent être **renseignés, pas `null`**. `loggedIn: true` seul ne prouve rien — le jeton, lui, a toujours survécu. Ces commandes ne coûtent aucun jeton d'API ; un argument libre serait en revanche traité comme un prompt.

2. **Le second rebuild doit être silencieux.** Reconstruire une seconde fois dans la foulée : aucun onboarding, aucun dialogue de confiance. C'est ce qui distingue « le fichier a été écrit au bon endroit » de « le fichier a été relu au bon endroit ».

3. **Les deux vérifications existantes de `claude-settings`** (`tests/smoke.sh` l. 141-151) visent `~/.claude` en dur. Elles doivent continuer à passer sans modification, la variable désignant ce chemin. Si elles échouent, c'est que la valeur posée dans le Dockerfile n'est pas celle attendue — corriger le Dockerfile, jamais le test.

4. **L'image `web` hérite de l'`ENV`** sans rien déclarer. Le vérifier plutôt que le supposer, la couche web repassant `USER root` puis `USER dev` :

   ```bash
   docker run --rm -u dev devcontainer-web:dev printenv CLAUDE_CONFIG_DIR
   ```

## Suite

Rien de ce qui a été examiné dans la comparaison avec `holotable` ne reste en attente : les emprunts écartés le sont avec leur raison en §9 de la spec, pour que la question ne se repose pas. Le seul sujet qu'elle laisse ouvert est le filtrage du trafic sortant, que ni ce dépôt ni l'autre ne pratiquent — la §« Ce que le garde-fou ne protège pas » du README l'énonce déjà comme une limite assumée, et un proxy filtrant par SNI en serait la forme, le jour où le besoin se présente.
