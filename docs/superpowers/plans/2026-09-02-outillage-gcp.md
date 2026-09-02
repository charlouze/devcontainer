# Plan d'implémentation — outillage GCP du dev container

> **Pour les agents exécutants :** SOUS-SKILL REQUISE — utiliser
> `superpowers:subagent-driven-development` (recommandé) ou
> `superpowers:executing-plans` pour dérouler ce plan tâche par tâche. Les
> étapes utilisent la syntaxe à cases (`- [ ]`) pour le suivi.

**But :** poser les bornes que le design a rendues nécessaires — une règle de
garde-fou pour Terraform, la fermeture du trou seccomp dans les invariants, la
mise en cohérence de `/etc/subuid`, et la documentation de ce que le container
ne sait pas faire.

**Architecture :** aucune nouvelle image, aucun nouveau fichier de code. Quatre
fichiers de production sont modifiés (le moteur de règles, le module
d'invariants, le `Dockerfile` de l'image de base, la skill d'onboarding) et
trois fichiers de test les couvrent. Les deux livrables de prose — README et
rappel dans la skill — ne sont vérifiés que par relecture, et le plan le dit à
chaque fois que c'est le cas.

**Pile technique :** Node.js 22 (`node --test`, aucune dépendance externe),
Docker, bash. Le dépôt n'a pas de `package.json` : les tests se lancent par
`mise run test-unit`.

**Spec :** `docs/superpowers/specs/2026-09-02-outillage-gcp-design.md`

## Contraintes globales

- **Français partout** : commentaires, messages de commit, documentation,
  contenu des skills, sorties utilisateur.
- **Messages de commit sans préfixe conventionnel.** Pas de `feat:`, `docs:`,
  `chore:`. Descriptifs, à l'impératif ou au présent.
- **Aucune mention d'assistant** dans les commits : ni `Co-Authored-By`, ni
  `Claude-Session`, ni « Generated with ».
- **Repli à ~80 colonnes** dans les fichiers du dépôt (README, skills, specs,
  plans). Ne s'applique pas aux descriptions de PR.
- **Ne jamais travailler sur `main`.** Ce plan s'exécute sur la branche
  `worktree-outillage-gcp`, dans le worktree
  `.claude/worktrees/outillage-gcp`. Le nom distant diffère du nom local :
  pousser par `git push origin HEAD:outillage-gcp`.
- **Commandes de vérification** : `mise run test-unit` pour les tests unitaires,
  `mise run check` pour la séquence complète de la CI (tests, build des deux
  images, smoke test). Sous Windows, lancer depuis Git Bash — dans PowerShell,
  `bash` résout vers le lanceur WSL.
- **Version cible : 1.6.0**, portée à l'identique par `.claude-plugin/marketplace.json`
  et `plugin/.claude-plugin/plugin.json`. La majeure ne change pas, donc le tag
  `:1` du template reste tel quel.

---

## Structure des fichiers

| Fichier | Responsabilité | Tâche |
|---|---|---|
| `images/agent-base/guard/rules.cjs` | Moteur de règles pur du garde-fou — aucune E/S, aucune lecture d'environnement | 1 |
| `tests/unit/rules.test.cjs` | Couverture du moteur de règles | 1 |
| `tests/lib/devcontainer-invariants.cjs` | Ce qu'un `devcontainer.json` produit par la skill doit satisfaire | 2 |
| `tests/unit/devcontainer-invariants.test.cjs` | Couverture du module d'invariants | 2 |
| `plugin/skills/onboard-devcontainer/SKILL.md` | Liste de contrôle en prose (tâche 2) et rappel de clôture (tâche 4) | 2, 4 |
| `images/agent-base/Dockerfile` | Construction de l'image socle | 3 |
| `tests/smoke.sh` | Vérifications qui ne sont observables qu'à l'exécution | 3 |
| `README.md` | Documentation du dépôt | 4 |
| `plugin/skills/onboard-devcontainer/references/amorcer.md` | Mode « amorcer » de la skill | 4 |
| `.claude-plugin/marketplace.json`, `plugin/.claude-plugin/plugin.json` | Version publiée | 5 |

Cinq tâches, dans l'ordre. Les tâches 1 à 3 sont indépendantes entre elles et
peuvent être relues séparément. La tâche 4 rassemble les deux livrables de prose
parce qu'ils portent le même contenu à deux endroits — les relire séparément
ferait manquer une divergence entre eux. La tâche 5 vient en dernier : une
version ne se pose qu'une fois le contenu figé.

---

## Tâche 1 : règle de garde-fou pour Terraform

**Fichiers :**
- Modifier : `images/agent-base/guard/rules.cjs` — insérer après la règle
  `gcloud`, actuellement lignes 73-76
- Test : `tests/unit/rules.test.cjs` — ajouter après le test
  « le socle bloque firebase deploy mais pas les émulateurs », ligne 199

**Interfaces :**
- Consomme : `evaluate(payload, reglesProjet)` et les fabriques `bash(command)`
  / `read(file_path)`, déjà définies en tête de `tests/unit/rules.test.cjs`
  (lignes 6-13). `evaluate` rend `null` quand la commande passe, et un objet
  non nul quand elle est refusée.
- Produit : rien que les tâches suivantes consomment. `BASH_RULES` gagne deux
  entrées ; sa forme — un tableau de paires `[RegExp, message]` — ne change pas.

- [ ] **Étape 1 : écrire les tests qui échouent**

À ajouter dans `tests/unit/rules.test.cjs`, à la suite du test
« le socle bloque firebase deploy mais pas les émulateurs » :

```js
// Le préfixe (?:-\S+\s+)* des deux règles absorbe les options globales, qui se
// glissent entre la commande et le verbe. Ce n'est pas décoratif :
// `terraform -chdir=infra apply` est la forme ordinaire dès que le Terraform
// vit dans un sous-répertoire, et sans ce groupe elle passerait sous les deux
// règles. Même raisonnement que le préfixe des règles `git push`.
test('le socle bloque les commandes Terraform qui écrivent', () => {
  for (const commande of [
    'terraform apply',
    'terraform apply -auto-approve',
    'terraform -chdir=infra apply',
    'terraform -chdir=infra destroy -auto-approve',
    'tofu apply',
    'terraform import google_compute_instance.jeu projects/p/zones/z/instances/i',
    'terraform force-unlock 1234',
    'terraform taint google_compute_instance.jeu',
    'echo pret; terraform destroy',
    '(terraform apply)',
  ]) {
    assert.ok(evaluate(bash(commande), null), commande);
  }
});

test("le socle bloque la réécriture de l'état Terraform", () => {
  for (const commande of [
    'terraform state rm google_compute_instance.jeu',
    'terraform state mv a b',
    'terraform -chdir=infra state push fichier.tfstate',
    'terraform state replace-provider a b',
  ]) {
    assert.ok(evaluate(bash(commande), null), commande);
  }
});

// `plan` reste libre : sans Application Default Credentials il échoue de
// lui-même. Le bloquer serait écrire une règle qui prétend protéger ce que
// l'absence de credential protège déjà.
test('le socle laisse passer Terraform en lecture', () => {
  for (const commande of [
    'terraform plan',
    'terraform -chdir=infra plan -out=tfplan',
    'terraform init -backend=false',
    'terraform fmt -check -recursive',
    'terraform validate',
    'terraform show tfplan',
    'terraform state list',
    'terraform state show google_compute_instance.jeu',
    'cat notes-terraform.md',
  ]) {
    assert.strictEqual(evaluate(bash(commande), null), null, commande);
  }
});
```

- [ ] **Étape 2 : lancer les tests et vérifier qu'ils échouent**

Lancer : `mise run test-unit`

Attendu : ÉCHEC. Les deux premiers tests échouent sur la première commande de
leur boucle (`evaluate` rend `null`, donc `assert.ok` refuse), avec le message
`terraform apply` puis `terraform state rm google_compute_instance.jeu`. Le
troisième test passe déjà — c'est normal, il vérifie qu'on ne casse rien.

- [ ] **Étape 3 : écrire les deux règles**

Dans `images/agent-base/guard/rules.cjs`, insérer juste après la règle `gcloud`
(celle dont le message est « Aucun accès à Google Cloud depuis ce container, par
construction. ») et avant la règle `npm publish` :

```js
  // Le préfixe (?:-\S+\s+)* absorbe les options globales, qui se glissent entre
  // la commande et le verbe. `terraform -chdir=infra apply` est la forme
  // ordinaire dès que le Terraform vit dans un sous-répertoire ; sans ce
  // groupe, elle passerait sous les deux règles. Même construction que le
  // préfixe des règles `git push`.
  //
  // `plan`, `init`, `fmt`, `validate` et `show` restent libres : sans
  // Application Default Credentials, `plan` échoue de lui-même. Une règle qui
  // le bloquerait prétendrait protéger ce que l'absence de credential protège
  // déjà.
  [
    /(^|[\s;&|(])(terraform|tofu)\s+(?:-\S+\s+)*(apply|destroy|import|force-unlock|taint|untaint)\b/,
    "Les commandes Terraform qui écrivent sont bloquées. `init`, `fmt`, " +
      '`validate`, `plan` et `show` restent disponibles.',
  ],
  // Les sous-commandes d'état ont un mot de plus, d'où une seconde entrée
  // plutôt qu'une alternance qui rendrait le premier motif illisible.
  [
    /(^|[\s;&|(])(terraform|tofu)\s+(?:-\S+\s+)*state\s+(rm|mv|push|replace-provider)\b/,
    "Réécrire l'état Terraform est bloqué : c'est le moyen détourné de " +
      "changer l'infrastructure sans passer par un `apply`.",
  ],
```

- [ ] **Étape 4 : lancer les tests et vérifier qu'ils passent**

Lancer : `mise run test-unit`

Attendu : SUCCÈS, sans aucun échec. Le compte de tests augmente de 3 par rapport
à la référence (78 avant cette tâche).

- [ ] **Étape 5 : committer**

```bash
git add images/agent-base/guard/rules.cjs tests/unit/rules.test.cjs
git commit -m "Le garde-fou bloque les commandes Terraform qui écrivent" -m "Même raison que pour gcloud : c'est une borne du dispositif, pas une préférence de dépôt. Les commandes de lecture — plan, init, fmt, validate, show — restent disponibles, l'absence de credential suffisant à protéger ce qu'elles pourraient atteindre."
```

---

## Tâche 2 : fermer le trou seccomp dans les invariants

**Contexte que l'exécutant n'a pas :** aujourd'hui, les invariants n'exigent que
la *présence* de `--security-opt no-new-privileges`. Un
`"--security-opt", "seccomp=unconfined"` ajouté à côté passe les neuf invariants
et toute la CI sans un mot. Or c'est exactement l'option qui autorise
`unshare(CLONE_NEWUSER)` — mesuré le 2026-09-02, cf. §3 du spec — donc la seule
qui rapproche d'un chemin d'évasion.

**Fichiers :**
- Modifier : `tests/lib/devcontainer-invariants.cjs` — constante à ajouter près
  de `OPTIONS_AUTORISEES` (ligne 18), libellé de l'invariant `runargs-securite`
  (lignes 39-42), boucle de contrôle des `runArgs` (lignes 115-122)
- Modifier : `plugin/skills/onboard-devcontainer/SKILL.md` — ligne
  `runargs-securite` de la liste de contrôle, lignes 101-103
- Test : `tests/unit/devcontainer-invariants.test.cjs`

**Interfaces :**
- Consomme : `verifier(texte)` et `INVARIANTS`, exportés par
  `tests/lib/devcontainer-invariants.cjs`. Dans le fichier de test, les
  fabriques `conforme()` (lignes 15-50) et `violations(modif)` (lignes 52-56)
  sont déjà définies : `violations` applique `modif` à un objet conforme et rend
  le tableau des **identifiants** de violations.
- Produit : `SECURITY_OPTS_AUTORISEES`, non exportée — usage interne au module.

- [ ] **Étape 1 : écrire les tests qui échouent**

À ajouter dans `tests/unit/devcontainer-invariants.test.cjs`, à la suite des
tests existants sur `runArgs` :

```js
// C'est l'option qui autorise unshare(CLONE_NEWUSER), donc la seule qui
// rapproche d'un chemin d'évasion. Elle passait les neuf invariants sans un
// mot : le trou était en face de la serrure.
test('une option de sécurité hors liste est refusée', () => {
  assert.deepStrictEqual(
    violations((c) => c.runArgs.push('--security-opt', 'seccomp=unconfined')),
    ['runargs-securite']
  );
});

// Docker accepte cette forme, pas nous : le contrôle de présence exige déjà la
// chaîne exacte, et l'uniformité vaut mieux ici que la tolérance. Deux
// violations remontent — la présence manquante et la valeur hors liste — d'où
// la comparaison sur un Set plutôt que sur le tableau.
test("la forme no-new-privileges:true est refusée", () => {
  assert.deepStrictEqual(
    new Set(violations((c) => (c.runArgs[1] = 'no-new-privileges:true'))),
    new Set(['runargs-securite'])
  );
});
```

- [ ] **Étape 2 : lancer les tests et vérifier qu'ils échouent**

Lancer : `mise run test-unit`

Attendu : ÉCHEC des deux nouveaux tests. Le premier rend `[]` au lieu de
`['runargs-securite']` — rien ne refuse l'option. Le second rend
`Set(['runargs-securite'])` **et passe déjà**, parce que le contrôle de présence
existant suffit à le faire échouer ; s'il passe dès cette étape, c'est attendu,
il verrouille un comportement qu'on ne veut pas voir régresser.

- [ ] **Étape 3 : écrire l'implémentation**

Dans `tests/lib/devcontainer-invariants.cjs`, ajouter la constante juste après
`OPTIONS_AUTORISEES` :

```js
// Liste blanche des VALEURS, en regard de la liste blanche des options. Sans
// elle, `--security-opt seccomp=unconfined` passait tous les invariants : le
// contrôle ne portait que sur la présence de no-new-privileges, jamais sur ce
// qui pouvait l'accompagner. Or seccomp=unconfined autorise
// unshare(CLONE_NEWUSER) — c'est la seule option qui rapproche d'une évasion.
const SECURITY_OPTS_AUTORISEES = ['no-new-privileges'];
```

Puis, dans la boucle qui parcourt déjà les paires de `runArgs`, ajouter le refus
à côté du contrôle des capabilities :

```js
  for (const [option, valeur] of options) {
    if (option === '--cap-add' && !CAPS_AUTORISEES.includes(valeur)) {
      refuse('runargs-securite', `capability hors liste : ${valeur}.`);
    }
    if (option === '--security-opt' && !SECURITY_OPTS_AUTORISEES.includes(valeur)) {
      refuse('runargs-securite', `option de sécurité hors liste : ${valeur}.`);
    }
    if (!OPTIONS_AUTORISEES.includes(option)) {
      refuse('runargs-parser', `option ${option} : le parser d'IntelliJ échouera dessus.`);
    }
  }
```

Enfin, mettre le libellé de l'invariant en accord :

```js
  {
    id: 'runargs-securite',
    libelle:
      'runArgs porte no-new-privileges, --cap-drop ALL, et aucune capability ni option de sécurité hors liste',
  },
```

- [ ] **Étape 4 : lancer les tests et vérifier qu'ils passent**

Lancer : `mise run test-unit`

Attendu : SUCCÈS. Vérifier en particulier que
« le template du plugin est conforme » et « un fichier conforme ne produit
aucune violation » passent toujours : le template ne porte que
`--security-opt no-new-privileges`, donc il reste valide.

- [ ] **Étape 5 : mettre la liste de contrôle de la skill en accord**

**Rien ne l'impose mécaniquement** : `tests/unit/skill-checklist.test.cjs` ne
vérifie que la présence de l'identifiant dans la prose, pas son libellé, et
l'identifiant ne change pas. Une liste de contrôle laissée en arrière passerait
la CI en silence. C'est donc une étape à ne pas sauter.

Dans `plugin/skills/onboard-devcontainer/SKILL.md`, remplacer la puce
`runargs-securite` par :

```markdown
- `runargs-securite` — `--security-opt no-new-privileges` et `--cap-drop ALL`
  sont présents, les seules capabilities rendues sont `CHOWN`, `FOWNER`,
  `DAC_OVERRIDE`, `SETUID`, `SETGID`, et `--security-opt` ne porte aucune autre
  valeur que `no-new-privileges`. En particulier jamais `seccomp=unconfined` :
  c'est l'option qui autorise la création d'un user namespace, donc la seule qui
  rapproche d'un chemin d'évasion.
```

- [ ] **Étape 6 : relancer les tests et committer**

Lancer : `mise run test-unit`

Attendu : SUCCÈS, y compris
« chaque invariant figure dans la liste de contrôle de la skill ».

```bash
git add tests/lib/devcontainer-invariants.cjs tests/unit/devcontainer-invariants.test.cjs plugin/skills/onboard-devcontainer/SKILL.md
git commit -m "Les invariants ferment la liste des options de sécurité" -m "Les invariants n'exigeaient que la présence de no-new-privileges : un seccomp=unconfined ajouté à côté passait toute la CI sans un mot. C'est pourtant la seule option qui autorise la création d'un user namespace, donc la seule qui rapproche d'un chemin d'évasion."
```

---

## Tâche 3 : `/etc/subuid` et `/etc/subgid`

**Contexte que l'exécutant n'a pas :** l'image renomme l'utilisateur `vscode` en
`dev` par `usermod --login`, qui ne met à jour ni `/etc/subuid` ni
`/etc/subgid`. Les deux portent encore `vscode:100000:65536`. On les vide plutôt
que de les renommer : une plage subuid n'a aucun usage dans un container qui ne
doit jamais créer de user namespace, et un fichier vide est un second verrou là
où un fichier renommé n'aurait été qu'une cohérence de nom.

**Fichiers :**
- Modifier : `images/agent-base/Dockerfile` — après le bloc `usermod`, lignes
  9-12
- Test : `tests/smoke.sh` — section « Utilisateur et toolchain », après la ligne
  `refute "sudo est neutralisé"`

**Interfaces :**
- Consomme : les helpers `check <description> <commande...>` (succès attendu) et
  `in_base '<commande shell>'` (exécute sous `dev` dans l'image de base, shell
  de login), définis en tête de `tests/smoke.sh`.
- Produit : rien que les tâches suivantes consomment.

- [ ] **Étape 1 : écrire l'assertion qui échoue**

Dans `tests/smoke.sh`, section « Utilisateur et toolchain », juste après la
ligne `refute "sudo est neutralisé"` :

```bash
# usermod --login ne suit ni /etc/subuid ni /etc/subgid, qui portaient encore
# `vscode`. Ils sont vidés dans l'image : une plage subuid n'a aucun usage dans
# un container qui ne doit jamais créer de user namespace. L'assertion existe
# pour qu'une mise à jour de l'image de base ne les réintroduise pas en silence.
# `-f` puis `! -s` et non `! -s` seul : ce dernier est vrai aussi pour un
# fichier absent, et l'absence n'est pas ce qu'on veut vérifier.
check  "/etc/subuid existe et est vide"          in_base 'test -f /etc/subuid && test ! -s /etc/subuid'
check  "/etc/subgid existe et est vide"          in_base 'test -f /etc/subgid && test ! -s /etc/subgid'
```

- [ ] **Étape 2 : construire l'image et vérifier que l'assertion échoue**

Lancer : `mise run build-base && bash tests/smoke.sh devcontainer-agent-base:dev`

Attendu : deux lignes `KO` — `/etc/subuid existe et est vide` et
`/etc/subgid existe et est vide` — et un code de sortie non nul. Les fichiers
contiennent encore `vscode:100000:65536`.

- [ ] **Étape 3 : vider les deux fichiers dans l'image**

Dans `images/agent-base/Dockerfile`, juste après le bloc `usermod`
(celui qui se termine par la ligne `sed -i "s/\bvscode\b/${USERNAME}/g" …`) :

```dockerfile
# usermod --login ne suit ni /etc/subuid ni /etc/subgid : ils portaient encore
# `vscode`. On les vide plutôt que de les renommer — une plage subuid n'a aucun
# usage dans un container qui ne doit jamais créer de user namespace, et un
# fichier vide est un verrou de plus là où un fichier renommé n'aurait été
# qu'une cohérence de nom. Vider et non supprimer : certains outils distinguent
# mal le fichier absent du fichier vide.
RUN : > /etc/subuid && : > /etc/subgid
```

- [ ] **Étape 4 : reconstruire et vérifier que l'assertion passe**

Lancer : `mise run build-base && bash tests/smoke.sh devcontainer-agent-base:dev`

Attendu : les deux lignes passent en `ok`, et aucune autre assertion ne
régresse.

- [ ] **Étape 5 : committer**

```bash
git add images/agent-base/Dockerfile tests/smoke.sh
git commit -m "L'image vide /etc/subuid et /etc/subgid" -m "usermod --login ne les avait pas suivis : ils nommaient encore l'utilisateur vscode, qui n'existe plus. Vidés plutôt que renommés — une plage subuid n'a aucun usage dans un container qui ne doit jamais créer de user namespace."
```

---

## Tâche 4 : documenter ce que le container ne sait pas faire

**Contexte que l'exécutant n'a pas :** une sonde exécutée le 2026-09-02 a établi
que la construction d'une image OCI dans ce dev container n'est possible qu'en
`root` avec `seccomp=unconfined`. Le détail et le tableau complet sont au §3 du
spec — **le lire avant d'écrire cette section**, le tableau ci-dessous en est un
extrait et non une reformulation libre.

Deux livrables portent le même contenu à deux endroits : le README, lu par qui
travaille sur ce dépôt-ci, et la skill, lue par qui branche un projet. Ils sont
dans la même tâche parce que les relire séparément ferait manquer une divergence
entre eux.

**Rien ici n'est vérifié mécaniquement.** C'est de la relecture, et c'est le
seul filet.

**Fichiers :**
- Modifier : `README.md` — nouvelle section, à insérer entre
  `## Publier une version` et `## Ce que le garde-fou ne protège pas`
  (actuellement ligne 314), pour que les deux sections de limites se suivent
- Modifier : `plugin/skills/onboard-devcontainer/SKILL.md` — paragraphe de
  clôture, lignes 124-132
- Modifier : `plugin/skills/onboard-devcontainer/references/amorcer.md` — §4
  « Dire la suite, dans l'ordre »

**Interfaces :** aucune. Trois fichiers de prose.

- [ ] **Étape 1 : écrire la section du README**

Insérer avant `## Ce que le garde-fou ne protège pas` :

```markdown
## Ce que le container ne sait pas faire

**Il ne construit pas d'image OCI.** Ni `docker build` — il n'y a pas de socket
Docker, et le monter serait une évasion en une commande — ni buildah ou podman
en rootless.

Mesuré le 2026-09-02, avec buildah 1.28 dans `devcontainer-web:1` sur Docker
29.6.2 :

| Configuration | user namespace | `FROM scratch` | avec `apt-get` |
|---|---|---|---|
| `runArgs` du template | refusé | non | non |
| `docker run` nu, sans aucune option | refusé | non | non |
| `+ seccomp=unconfined`, user `dev` | ok | oui | non |
| idem sans `no-new-privileges`, caps par défaut | ok | oui | non |
| `seccomp=unconfined`, user `root` | ok | oui | oui |

**Le durcissement de ce dépôt n'est pas en cause**, et c'est le point à retenir :
ni `no-new-privileges` ni `--cap-drop ALL` n'empêchent la création du user
namespace. C'est le profil seccomp par défaut de Docker qui refuse
`unshare(CLONE_NEWUSER)` — un `docker run` sans la moindre option échoue
identiquement. En retirer ne débloquerait rien.

Le verrou suivant, lui, ne s'ouvre que par root : une fois seccomp levé,
`newuidmap` reste refusé, buildah retombe sur un mapping à un seul UID, et le
simple pull de `debian:bookworm-slim` casse sur `/etc/gshadow`. Or root rend le
garde-fou atteignable, puisque `/etc/claude-guard/enabled` est en 0444 root.
Construire en local et confiner l'agent s'excluent.

D'où l'orientation : **le container rédige et vérifie statiquement, la CI
construit et déploie.** `terraform fmt`, `validate` et un linter de Dockerfile
fonctionnent sans credential ; `apply` et `docker build` n'ont pas leur place
ici.
```

- [ ] **Étape 2 : ajouter le rappel dans la skill**

Dans `plugin/skills/onboard-devcontainer/SKILL.md`, à la fin du paragraphe de
clôture qui commence par « Termine en rappelant à l'humain ce que le garde-fou
**ne** protège **pas** », ajouter :

```markdown
Dis-lui enfin ce que le container **ne sait pas faire** : il ne construit pas
d'image OCI. Pas de socket Docker, et le rootless échoue aussi — la seule
configuration qui construit est `root` + `seccomp=unconfined`, ce qui rendrait le
garde-fou atteignable. Le blocage vient du profil seccomp par défaut de Docker et
non du durcissement, donc en retirer ne débloquerait rien. La construction et le
déploiement se font en CI ; le container rédige et vérifie statiquement.
```

- [ ] **Étape 3 : ajouter le rappel dans le mode « amorcer »**

Dans `plugin/skills/onboard-devcontainer/references/amorcer.md`, §4
« Dire la suite, dans l'ordre », après le paragraphe qui avertit que le projet
vivra dans un volume Docker :

```markdown
Dis-lui aussi que **le container ne construira pas d'image OCI** — la question
se pose tôt sur un projet qui naît, et plus tôt encore s'il vise un déploiement
conteneurisé. La raison est au README du dépôt des images, section « Ce que le
container ne sait pas faire » : ce n'est pas un réglage à ajuster, c'est une
propriété du dispositif.
```

- [ ] **Étape 4 : vérifier que rien n'est cassé**

Lancer : `mise run test-unit`

Attendu : SUCCÈS. Aucun test ne couvre ce contenu, mais
`skill-checklist.test.cjs` vérifie le frontmatter et les renvois par mode :
l'édition ne doit pas les avoir déplacés.

- [ ] **Étape 5 : relire les trois textes côte à côte**

Vérifier à l'œil, avant de committer :
- le README et la skill disent la même chose, sans se contredire sur la cause
  (le seccomp par défaut de Docker, jamais le durcissement du dépôt) ;
- le repli est à ~80 colonnes dans les trois fichiers ;
- `amorcer.md` renvoie bien vers le titre exact de la section du README.

- [ ] **Étape 6 : committer**

```bash
git add README.md plugin/skills/onboard-devcontainer/SKILL.md plugin/skills/onboard-devcontainer/references/amorcer.md
git commit -m "Documenter que le container ne construit pas d'image OCI" -m "Le README pour qui travaille sur ce dépôt-ci, la skill pour qui branche un projet. Les deux insistent sur le même point : le blocage vient du profil seccomp par défaut de Docker et non du durcissement, donc en retirer ne débloquerait rien."
```

---

## Tâche 5 : version 1.6.0

**Contexte que l'exécutant n'a pas :** la version du plugin est couplée à celle
des images. `tests/unit/plugin-manifests.test.cjs` échoue si les deux manifestes
divergent. La publication elle-même se fait par un tag git sur `main` **après**
le merge de la PR — elle ne fait pas partie de ce plan.

**Fichiers :**
- Modifier : `.claude-plugin/marketplace.json` — champ `version` de l'entrée
  `plugins[0]`, actuellement `1.5.0`
- Modifier : `plugin/.claude-plugin/plugin.json` — champ `version`, actuellement
  `1.5.0`

**Interfaces :** aucune.

- [ ] **Étape 1 : porter les deux manifestes à 1.6.0**

Dans `.claude-plugin/marketplace.json`, remplacer `"version": "1.5.0"` par
`"version": "1.6.0"`. Dans `plugin/.claude-plugin/plugin.json`, faire de même.

Ne pas toucher au tag `:1` de
`plugin/skills/onboard-devcontainer/references/devcontainer.template.json` : la
majeure ne change pas, et un tag figé casserait l'invariant `image-tag`.

- [ ] **Étape 2 : vérifier les manifestes**

Lancer : `mise run test-unit`

Attendu : SUCCÈS, y compris les tests de `plugin-manifests.test.cjs` qui
comparent les deux versions et contrôlent le tag du template.

- [ ] **Étape 3 : rejouer la séquence complète de la CI**

Lancer : `mise run check`

Attendu : SUCCÈS de bout en bout — tests unitaires, build d'`agent-base`, build
de `web`, puis smoke test sur les deux images, assertions `/etc/subuid` de la
tâche 3 comprises. C'est la dernière vérification avant de proposer le merge.

- [ ] **Étape 4 : committer et pousser**

```bash
git add .claude-plugin/marketplace.json plugin/.claude-plugin/plugin.json
git commit -m "Version 1.6.0"
git push origin HEAD:outillage-gcp
```

---

## Après le plan

L'implémentation vit sur la même branche que le spec, donc sur la PR #12 —
qui ne portait jusque-là que le document de conception. Deux options au moment
de conclure, à trancher avec l'humain plutôt que seul : élargir la PR existante,
ou ouvrir une PR d'implémentation distincte au-dessus. Le spec annonce la
seconde forme dans sa description de PR.

La publication de la 1.6.0 — `git tag v1.6.0 && git push origin v1.6.0` sur un
`main` à jour — vient **après** le merge, et suit la procédure du README
§ « Publier une version ». L'ordre compte : chaque container installe le plugin
depuis la marketplace publiée.
