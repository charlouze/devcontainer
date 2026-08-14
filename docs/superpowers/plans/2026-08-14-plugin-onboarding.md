# Plugin Claude Code d'onboarding — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer le plugin Claude Code `devcontainer` — un point d'entrée `/devcontainer-init` qui branche, migre, amorce ou met à jour le dev container d'un dépôt sur les images publiées par ce dépôt.

**Architecture:** Le dépôt devient sa propre marketplace Claude Code et expose un plugin contenant une commande et une skill. La skill est **en prose** : elle lit le dépôt et écrit les fichiers elle-même, sans code exécutable, pour que l'onboarding ne demande rien au poste hôte (§14.3 du spec : le container vient d'abord, l'hôte n'a ni node ni pnpm). Ce que la prose ne peut pas garantir seule — qu'un `devcontainer.json` produit conserve bien le durcissement — est tenu par un module d'invariants testé unitairement, qui valide le template et les sorties attendues des fixtures, et dont la liste est reprise mot pour mot dans la liste de contrôle finale de la skill.

**Tech Stack:** Markdown (skill et commande), JSON (manifestes de marketplace et de plugin, template JSONC), Node.js `node:test` pour les invariants, mise, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-14-devcontainer-base-design.md` (§14 pour le plugin, §7.3 pour le format des règles projet, §13 pour le contrat côté projet)

**Plan précédent:** `docs/superpowers/plans/2026-08-14-devcontainer-images.md` — intégralement exécuté, publié en `v1.0.0`. Ce plan-ci en reprend deux dettes explicites : la ligne `charlouze/devcontainer` volontairement absente de `plugins.d/00-base.txt`, et le point de vérification n°4 (`claude plugin install` en non-interactif, jamais éprouvé autrement qu'avec un `claude` bouchonné).

**Hors périmètre :** la migration de Compte-de-Famille (§17 du spec). Elle fera l'objet d'un plan séparé, écrit une fois le plugin éprouvé. La fixture du mode « migrer » est calquée sur ce dépôt pour que la migration réelle soit ensuite une simple comparaison.

## Global Constraints

- **Langue.** Commentaires, messages, contenu des skills et sorties utilisateur en **français**, y compris la `description` en frontmatter des skills — c'est la convention du dépôt, et elle prime ici sur l'usage anglophone de l'écosystème.
- **Fins de ligne.** LF partout (`.gitattributes` déjà en place).
- **La skill ne dépend d'aucun outil du poste hôte.** Ni node, ni jq, ni script. Elle lit et écrit des fichiers, rien d'autre. Toute tentation d'y appeler un binaire est un défaut de conception, pas une optimisation.
- **Un seul template.** Le `devcontainer.json` de référence vit **dans le plugin** (`plugin/skills/onboard-devcontainer/references/devcontainer.template.json`) et nulle part ailleurs. Le plugin installé ne transporte que `plugin/` : un template resté à la racine du dépôt serait invisible depuis une session, donc jamais celui qui est appliqué.
- **Le tag d'image est porté par le template.** La skill ne calcule ni ne devine de tag : elle copie celui du template. Un test vérifie qu'il s'accorde avec la version déclarée dans `plugin.json`. C'est ce qui garantit — spec §14 — que le plugin ne pose jamais un tag inexistant.
- **Le socle du garde-fou n'est jamais touché.** La skill peut écrire un `.devcontainer/guard-rules.json`, qui ne fait qu'**ajouter** au socle. Elle ne modifie jamais `managed-settings.json`, ni rien sous `/etc/claude-*` ou `/usr/local/lib/claude-guard/`.
- **Rien n'est supprimé sans que le diff ait été montré** et validé par l'humain. Vaut pour les fichiers rendus inutiles par la migration comme pour les clés retirées d'un `devcontainer.json` existant.
- **Version du plugin = version des images.** `plugin.json` et `marketplace.json` portent la même version que le tag publié.
- **Images publiées :** `ghcr.io/charlouze/devcontainer-agent-base` et `ghcr.io/charlouze/devcontainer-web`, tags `1`, `1.x.y`, sha.

---

## Structure des fichiers

| Fichier | Responsabilité |
|---|---|
| `tests/lib/jsonc.cjs` | Lecture des `devcontainer.json` : commentaires et virgules traînantes |
| `tests/lib/devcontainer-invariants.cjs` | **Module pur** : liste des invariants de durcissement et vérification d'un fichier |
| `tests/lib/check-devcontainer.cjs` | CLI autour du module, pour vérifier un fichier à la main |
| `tests/unit/jsonc.test.cjs` | Tests du lecteur JSONC |
| `tests/unit/devcontainer-invariants.test.cjs` | Tests des invariants + validation du template |
| `tests/unit/plugin-manifests.test.cjs` | Cohérence marketplace ↔ plugin ↔ `plugins.d` ↔ tag du template |
| `tests/unit/skill-checklist.test.cjs` | Chaque invariant du module figure dans la liste de contrôle de la skill |
| `tests/unit/fixtures-onboarding.test.cjs` | Chaque sortie attendue des fixtures respecte les invariants |
| `.claude-plugin/marketplace.json` | Le dépôt est sa propre marketplace |
| `plugin/.claude-plugin/plugin.json` | Manifeste du plugin |
| `plugin/commands/devcontainer-init.md` | Point d'entrée `/devcontainer-init` |
| `plugin/skills/onboard-devcontainer/SKILL.md` | Détection du mode, règles communes, liste de contrôle finale |
| `plugin/skills/onboard-devcontainer/references/devcontainer.template.json` | Le template, commentaires compris |
| `plugin/skills/onboard-devcontainer/references/brancher.md` | Mode « brancher » |
| `plugin/skills/onboard-devcontainer/references/migrer.md` | Mode « migrer » |
| `plugin/skills/onboard-devcontainer/references/amorcer.md` | Mode « amorcer » |
| `plugin/skills/onboard-devcontainer/references/mettre-a-jour.md` | Mode « mettre à jour » |
| `tests/fixtures/onboarding/<cas>/<dépôt>/` | Dépôt d'entrée du cas |
| `tests/fixtures/onboarding/<cas>/attendu/` | Sortie attendue, oracle du rejeu manuel |

**Note de décomposition n°1 — le template déménage.** Le plan précédent l'avait posé en `templates/web/devcontainer.json`, conformément à la §4 du spec. Il descend dans le plugin et l'ancien emplacement est supprimé. Deux copies auraient dérivé, et c'est la copie invisible depuis une session installée qui aurait été la mauvaise.

**Note de décomposition n°2 — pourquoi du code dans un livrable en prose.** Une skill ne se teste qu'en la rejouant, avec la variabilité que ça implique. Or le mode d'échec qui compte n'est pas « la skill a mal deviné un port » — ça se voit — mais « le `devcontainer.json` produit a perdu `no-new-privileges` », qui ne se voit pas et qui vide le container de sa raison d'être. Cette classe-là est mécanique : elle est donc tenue par du code, et la liste de contrôle de la skill n'en est que le reflet, tenu en accord par un test.

---

## Task 1: Invariants d'un devcontainer.json et généralisation du template

Pose l'oracle mécanique avant tout le reste : ce qu'un `devcontainer.json` doit satisfaire, quel que soit le mode qui l'a produit.

**Files:**
- Create: `tests/lib/jsonc.cjs`
- Create: `tests/lib/devcontainer-invariants.cjs`
- Create: `tests/lib/check-devcontainer.cjs`
- Create: `tests/unit/jsonc.test.cjs`
- Create: `tests/unit/devcontainer-invariants.test.cjs`
- Create: `plugin/skills/onboard-devcontainer/references/devcontainer.template.json`
- Delete: `templates/web/devcontainer.json`
- Test: `mise run test-unit`

**Interfaces:**
- Consumes: rien
- Produces:
  - `parseJsonc(texte) → objet` — lève sur JSON réellement invalide
  - `INVARIANTS` — tableau de `{ id, libelle }`, l'`id` étant la clé partagée avec la liste de contrôle de la skill
  - `verifier(texte) → Array<{ id, message }>` — tableau vide si le fichier est conforme
  - `node tests/lib/check-devcontainer.cjs <fichier>` — sort en 0 si conforme, 1 sinon, violations sur stdout
  - le template, à `plugin/skills/onboard-devcontainer/references/devcontainer.template.json`

- [ ] **Step 1: Écrire les tests du lecteur JSONC**

Créer `tests/unit/jsonc.test.cjs` :

```js
'use strict';

const test = require('node:test');
const assert = require('node:assert');

const { parseJsonc } = require('../lib/jsonc.cjs');

test('un commentaire de ligne est retiré', () => {
  assert.deepStrictEqual(parseJsonc('{\n  // note\n  "a": 1\n}'), { a: 1 });
});

test('un commentaire de bloc est retiré', () => {
  assert.deepStrictEqual(parseJsonc('{ /* note\n   suite */ "a": 1 }'), { a: 1 });
});

test('une chaîne contenant // survit', () => {
  assert.deepStrictEqual(parseJsonc('{ "a": "https://exemple.test/x" }'), {
    a: 'https://exemple.test/x',
  });
});

test('une chaîne contenant un guillemet échappé ne désynchronise pas la lecture', () => {
  assert.deepStrictEqual(parseJsonc('{ "a": "dit \\"bonjour\\"", "b": 1 }'), {
    a: 'dit "bonjour"',
    b: 1,
  });
});

test('une virgule traînante est tolérée', () => {
  assert.deepStrictEqual(parseJsonc('{ "a": [1, 2,], }'), { a: [1, 2] });
});

test('un JSON réellement invalide lève', () => {
  assert.throws(() => parseJsonc('{ "a": }'));
});
```

- [ ] **Step 2: Lancer pour vérifier l'échec**

Run: `mise run test-unit`
Expected: FAIL — `Cannot find module '../lib/jsonc.cjs'`

- [ ] **Step 3: Écrire le lecteur JSONC**

Créer `tests/lib/jsonc.cjs` :

```js
'use strict';

/**
 * Les devcontainer.json sont du JSONC : commentaires de ligne, commentaires de
 * bloc, virgules traînantes. JSON.parse refuse les trois. Les commentaires du
 * template sont un livrable à part entière — les lire, et donc les préserver,
 * n'est pas optionnel.
 *
 * Le découpage suit l'état « dans une chaîne » plutôt qu'une expression
 * régulière : un `//` dans une URL n'est pas un commentaire.
 */

function stripComments(texte) {
  let sortie = '';
  let i = 0;
  let dansChaine = false;

  while (i < texte.length) {
    const c = texte[i];

    if (dansChaine) {
      sortie += c;
      if (c === '\\') {
        sortie += texte[i + 1] ?? '';
        i += 2;
        continue;
      }
      if (c === '"') dansChaine = false;
      i += 1;
      continue;
    }

    if (c === '"') {
      dansChaine = true;
      sortie += c;
      i += 1;
      continue;
    }

    if (c === '/' && texte[i + 1] === '/') {
      while (i < texte.length && texte[i] !== '\n') i += 1;
      continue;
    }

    if (c === '/' && texte[i + 1] === '*') {
      i += 2;
      while (i < texte.length && !(texte[i] === '*' && texte[i + 1] === '/')) i += 1;
      i += 2;
      continue;
    }

    sortie += c;
    i += 1;
  }

  return sortie;
}

function stripTrailingCommas(texte) {
  let sortie = '';
  let dansChaine = false;

  for (let i = 0; i < texte.length; i += 1) {
    const c = texte[i];

    if (dansChaine) {
      sortie += c;
      if (c === '\\') {
        sortie += texte[i + 1] ?? '';
        i += 1;
        continue;
      }
      if (c === '"') dansChaine = false;
      continue;
    }

    if (c === '"') {
      dansChaine = true;
      sortie += c;
      continue;
    }

    if (c === ',') {
      let j = i + 1;
      while (j < texte.length && /\s/.test(texte[j])) j += 1;
      if (texte[j] === '}' || texte[j] === ']') continue;
    }

    sortie += c;
  }

  return sortie;
}

function parseJsonc(texte) {
  return JSON.parse(stripTrailingCommas(stripComments(texte)));
}

module.exports = { parseJsonc, stripComments, stripTrailingCommas };
```

- [ ] **Step 4: Lancer pour vérifier que les tests passent**

Run: `mise run test-unit`
Expected: PASS

- [ ] **Step 5: Écrire les tests des invariants**

Créer `tests/unit/devcontainer-invariants.test.cjs` :

```js
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const { verifier, INVARIANTS } = require('../lib/devcontainer-invariants.cjs');

const TEMPLATE = path.join(
  __dirname,
  '../../plugin/skills/onboard-devcontainer/references/devcontainer.template.json'
);

const conforme = () =>
  JSON.parse(
    JSON.stringify({
      name: 'Démo (agent sandbox)',
      image: 'ghcr.io/charlouze/devcontainer-web:1',
      containerUser: 'root',
      remoteUser: 'dev',
      containerEnv: { GCLOUD_PROJECT: 'demo-dev' },
      mounts: [
        'source=agent-claude,target=/home/dev/.claude,type=volume',
        'source=demo-cache,target=/home/dev/.cache,type=volume',
        'source=agent-pnpm-store,target=/home/dev/.cache/pnpm-store,type=volume',
        'source=agent-playwright,target=/home/dev/.cache/ms-playwright,type=volume',
        'source=demo-history,target=/home/dev/.history,type=volume',
      ],
      runArgs: [
        '--security-opt',
        'no-new-privileges',
        '--cap-drop',
        'ALL',
        '--cap-add',
        'CHOWN',
        '--cap-add',
        'FOWNER',
        '--cap-add',
        'DAC_OVERRIDE',
        '--cap-add',
        'SETUID',
        '--cap-add',
        'SETGID',
      ],
      forwardPorts: [4200],
      portsAttributes: { 4200: { label: 'App Angular' } },
      postCreateCommand: '/usr/local/share/devcontainer/post-create.sh',
    })
  );

const violations = (modif) => {
  const config = conforme();
  modif(config);
  return verifier(JSON.stringify(config)).map((v) => v.id);
};

test('un fichier conforme ne produit aucune violation', () => {
  assert.deepStrictEqual(verifier(JSON.stringify(conforme())), []);
});

test('le template du plugin est conforme', () => {
  assert.deepStrictEqual(verifier(fs.readFileSync(TEMPLATE, 'utf8')), []);
});

test('une image hors du dépôt est refusée', () => {
  assert.deepStrictEqual(violations((c) => (c.image = 'node:22')), ['image-tag']);
});

test('un tag figé est refusé : les projets suivent la majeure', () => {
  assert.deepStrictEqual(
    violations((c) => (c.image = 'ghcr.io/charlouze/devcontainer-web:1.0.0')),
    ['image-tag']
  );
});

test('remoteUser root est refusé', () => {
  assert.deepStrictEqual(violations((c) => (c.remoteUser = 'root')), ['utilisateurs']);
});

test('un postCreateCommand détourné est refusé', () => {
  assert.deepStrictEqual(
    violations((c) => (c.postCreateCommand = 'bash .devcontainer/post-create.sh')),
    ['post-create']
  );
});

test('retirer no-new-privileges est refusé', () => {
  assert.deepStrictEqual(violations((c) => (c.runArgs = ['--cap-drop', 'ALL'])), [
    'runargs-securite',
  ]);
});

test('une capability non prévue est refusée', () => {
  assert.deepStrictEqual(
    violations((c) => c.runArgs.push('--cap-add', 'SYS_ADMIN')),
    ['runargs-securite']
  );
});

test('une option que le parser IntelliJ ne connaît pas est refusée', () => {
  assert.deepStrictEqual(violations((c) => c.runArgs.push('--memory', '8g')), [
    'runargs-parser',
  ]);
});

test('un volume de login propre au projet est refusé : le login est mutualisé', () => {
  assert.deepStrictEqual(
    violations(
      (c) =>
        (c.mounts[0] = 'source=demo-claude,target=/home/dev/.claude,type=volume')
    ),
    ['volumes']
  );
});

test('un cache partagé entre projets est refusé : deux backends IDE s\'y disputeraient', () => {
  assert.deepStrictEqual(
    violations((c) => (c.mounts[1] = 'source=agent-cache,target=/home/dev/.cache,type=volume')),
    ['volumes']
  );
});

test('un montage manquant est refusé', () => {
  assert.deepStrictEqual(violations((c) => c.mounts.pop()), ['volumes']);
});

test('un bind mount de l\'hôte est refusé', () => {
  assert.deepStrictEqual(
    violations((c) =>
      c.mounts.push('source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind')
    ),
    ['pas-de-socket-docker']
  );
});

test('une variable qui prétend piloter le garde-fou est refusée', () => {
  assert.deepStrictEqual(violations((c) => (c.containerEnv.CDF_SANDBOX = '1')), [
    'pas-de-variable-garde-fou',
  ]);
});

test('un port ouvert sans libellé est refusé', () => {
  assert.deepStrictEqual(violations((c) => c.forwardPorts.push(8080)), ['ports-libelles']);
});

test('un fichier illisible produit une violation unique', () => {
  const ids = verifier('{ pas du json').map((v) => v.id);
  assert.deepStrictEqual(ids, ['json']);
});

test('chaque invariant porte un id unique et un libellé', () => {
  const ids = INVARIANTS.map((i) => i.id);
  assert.strictEqual(new Set(ids).size, ids.length);
  for (const invariant of INVARIANTS) {
    assert.ok(invariant.libelle.length > 10, `libellé trop court : ${invariant.id}`);
  }
});
```

- [ ] **Step 6: Lancer pour vérifier l'échec**

Run: `mise run test-unit`
Expected: FAIL — `Cannot find module '../lib/devcontainer-invariants.cjs'`

- [ ] **Step 7: Écrire le module d'invariants**

Créer `tests/lib/devcontainer-invariants.cjs` :

```js
'use strict';

/**
 * Ce qu'un devcontainer.json produit par la skill d'onboarding doit satisfaire,
 * quel que soit le mode qui l'a produit.
 *
 * Ces règles sont mécaniques, donc tenues par du code. La liste de contrôle
 * finale de plugin/skills/onboard-devcontainer/SKILL.md en est le reflet en
 * prose, et un test (tests/unit/skill-checklist.test.cjs) vérifie que les deux
 * restent en accord : toute modification ici est à répercuter là-bas.
 */

const { parseJsonc } = require('./jsonc.cjs');

const IMAGE = /^ghcr\.io\/charlouze\/devcontainer-(agent-base|web):\d+$/;
const POST_CREATE = '/usr/local/share/devcontainer/post-create.sh';
const CAPS_AUTORISEES = ['CHOWN', 'FOWNER', 'DAC_OVERRIDE', 'SETUID', 'SETGID'];
const OPTIONS_AUTORISEES = ['--security-opt', '--cap-drop', '--cap-add'];

// Cibles dont la source est imposée : le login et les caches content-addressed
// sont mutualisés entre projets, le partage y étant sûr par construction.
const MONTAGES_PARTAGES = {
  '/home/dev/.claude': 'agent-claude',
  '/home/dev/.cache/pnpm-store': 'agent-pnpm-store',
  '/home/dev/.cache/ms-playwright': 'agent-playwright',
};

// Cibles dont la source doit être propre au projet : deux containers ouverts en
// même temps ne doivent se disputer ni le backend JetBrains ni l'historique.
const MONTAGES_PROJET = ['/home/dev/.cache', '/home/dev/.history'];

const INVARIANTS = [
  { id: 'image-tag', libelle: "l'image est une image du dépôt, sur un tag de majeure (`:1`)" },
  { id: 'utilisateurs', libelle: 'containerUser vaut root et remoteUser vaut dev' },
  { id: 'post-create', libelle: `postCreateCommand vaut exactement ${POST_CREATE}` },
  {
    id: 'runargs-securite',
    libelle: 'runArgs porte no-new-privileges, --cap-drop ALL, et aucune capability hors liste',
  },
  {
    id: 'runargs-parser',
    libelle: 'runArgs ne contient que --security-opt, --cap-drop et --cap-add',
  },
  { id: 'volumes', libelle: 'les cinq montages attendus, partagés ou préfixés par le projet' },
  { id: 'pas-de-socket-docker', libelle: "aucun montage de type bind depuis l'hôte" },
  {
    id: 'pas-de-variable-garde-fou',
    libelle: "aucune variable d'environnement ne prétend piloter le garde-fou",
  },
  { id: 'ports-libelles', libelle: 'chaque port de forwardPorts porte un libellé' },
];

function paires(liste) {
  const sortie = [];
  for (let i = 0; i < liste.length; i += 2) sortie.push([liste[i], liste[i + 1]]);
  return sortie;
}

function champsDuMontage(montage) {
  const champs = {};
  for (const morceau of String(montage).split(',')) {
    const index = morceau.indexOf('=');
    if (index > 0) champs[morceau.slice(0, index)] = morceau.slice(index + 1);
  }
  return champs;
}

function verifier(texte) {
  const violations = [];
  const refuse = (id, message) => violations.push({ id, message });

  let config;
  try {
    config = parseJsonc(texte);
  } catch (erreur) {
    return [{ id: 'json', message: `fichier illisible : ${erreur.message}` }];
  }

  if (!IMAGE.test(String(config.image || ''))) {
    refuse('image-tag', `image inattendue : ${config.image}. Attendu un tag de majeure.`);
  }

  if (config.containerUser !== 'root' || config.remoteUser !== 'dev') {
    refuse(
      'utilisateurs',
      `containerUser/remoteUser valent ${config.containerUser}/${config.remoteUser}, attendu root/dev.`
    );
  }

  if (config.postCreateCommand !== POST_CREATE) {
    refuse('post-create', `postCreateCommand vaut ${config.postCreateCommand}.`);
  }

  const runArgs = Array.isArray(config.runArgs) ? config.runArgs : [];
  const options = paires(runArgs);
  const contient = (option, valeur) =>
    options.some(([o, v]) => o === option && v === valeur);

  if (!contient('--security-opt', 'no-new-privileges') || !contient('--cap-drop', 'ALL')) {
    refuse('runargs-securite', 'no-new-privileges et --cap-drop ALL sont obligatoires.');
  }
  for (const [option, valeur] of options) {
    if (option === '--cap-add' && !CAPS_AUTORISEES.includes(valeur)) {
      refuse('runargs-securite', `capability hors liste : ${valeur}.`);
    }
    if (!OPTIONS_AUTORISEES.includes(option)) {
      refuse('runargs-parser', `option ${option} : le parser d'IntelliJ échouera dessus.`);
    }
  }

  const montages = new Map();
  for (const montage of config.mounts || []) {
    const champs = champsDuMontage(montage);
    montages.set(champs.target, champs);
    if (champs.type === 'bind') {
      refuse('pas-de-socket-docker', `montage bind depuis l'hôte : ${montage}.`);
    }
  }
  for (const [cible, source] of Object.entries(MONTAGES_PARTAGES)) {
    if (!montages.has(cible)) refuse('volumes', `montage manquant : ${cible}.`);
    else if (montages.get(cible).source !== source) {
      refuse('volumes', `${cible} doit venir du volume partagé ${source}.`);
    }
  }
  for (const cible of MONTAGES_PROJET) {
    if (!montages.has(cible)) refuse('volumes', `montage manquant : ${cible}.`);
    else if (/^agent-/.test(montages.get(cible).source || '')) {
      refuse('volumes', `${cible} doit être propre au projet, pas un volume agent-*.`);
    }
  }

  for (const cle of Object.keys(config.containerEnv || {})) {
    if (/GUARD|SANDBOX/i.test(cle)) {
      refuse(
        'pas-de-variable-garde-fou',
        `${cle} : le garde-fou s'active par marqueur root-only, jamais par variable.`
      );
    }
  }

  const libelles = config.portsAttributes || {};
  for (const port of config.forwardPorts || []) {
    if (!libelles[String(port)] || !libelles[String(port)].label) {
      refuse('ports-libelles', `le port ${port} est ouvert sans libellé.`);
    }
  }

  return violations;
}

module.exports = { verifier, INVARIANTS, IMAGE, POST_CREATE };
```

Créer `tests/lib/check-devcontainer.cjs` :

```js
#!/usr/bin/env node
'use strict';

// Vérifie à la main un devcontainer.json produit par la skill d'onboarding.
// La skill elle-même ne l'appelle pas : elle ne doit rien exiger du poste hôte.

const fs = require('node:fs');
const { verifier } = require('./devcontainer-invariants.cjs');

const fichier = process.argv[2];
if (!fichier) {
  console.error('usage : node tests/lib/check-devcontainer.cjs <devcontainer.json>');
  process.exit(2);
}

const violations = verifier(fs.readFileSync(fichier, 'utf8'));
if (violations.length === 0) {
  console.log(`${fichier} : conforme`);
  process.exit(0);
}
for (const { id, message } of violations) console.log(`[${id}] ${message}`);
process.exit(1);
```

- [ ] **Step 8: Déplacer et généraliser le template**

Créer `plugin/skills/onboard-devcontainer/references/devcontainer.template.json` avec le contenu ci-dessous. C'est l'actuel `templates/web/devcontainer.json`, dont les valeurs propres à Compte-de-Famille deviennent des marques de substitution, et dont les commentaires — qui sont le livrable autant que le JSON — sont conservés mot pour mot :

```json
{
  // Les marques <…> sont à remplacer. Tout le reste se recopie tel quel : les
  // commentaires expliquent des réglages dont le symptôme, quand ils manquent,
  // ne mène pas à la cause.
  "name": "<Nom du projet> (agent sandbox)",
  "image": "ghcr.io/charlouze/devcontainer-web:1",

  // Le clone-from-VCS est fait par un container helper tournant en root :
  // l'arbre appartient à root et JetBrains doit le rendre à `dev` avant les
  // lifecycle scripts, ce qui exige root et CAP_CHOWN. L'IDE, les terminaux et
  // les lifecycle scripts tournent ensuite sous `remoteUser`.
  "containerUser": "root",
  "remoteUser": "dev",

  // Aucun credential cloud n'entre dans le container. Combiné aux variables
  // d'émulateur ci-dessous, le SDK Admin ne peut atteindre que l'émulateur
  // local : sans Application Default Credentials, il échoue au lieu d'écrire
  // dans le vrai projet.
  //
  // Aucune variable ne pilote le garde-fou : il s'active sur la présence de
  // /etc/claude-guard/enabled, root et non falsifiable, précisément parce que
  // l'agent contrôle l'environnement des processus qu'il lance.
  "containerEnv": {
    "FIRESTORE_EMULATOR_HOST": "127.0.0.1:8080",
    "FIREBASE_AUTH_EMULATOR_HOST": "127.0.0.1:9099",
    "GCLOUD_PROJECT": "<projet-firebase>",
    "GOOGLE_CLOUD_PROJECT": "<projet-firebase>"
  },

  // Les volumes `agent-*` sont volontairement partagés entre projets : login et
  // plugins une seule fois, caches content-addressed où le partage est sûr par
  // construction. Les deux autres sont préfixés par le projet — deux containers
  // ouverts en même temps ne doivent se disputer ni le backend JetBrains ni
  // l'historique de shell.
  "mounts": [
    "source=agent-claude,target=/home/dev/.claude,type=volume",
    "source=<slug>-cache,target=/home/dev/.cache,type=volume",
    "source=agent-pnpm-store,target=/home/dev/.cache/pnpm-store,type=volume",
    "source=agent-playwright,target=/home/dev/.cache/ms-playwright,type=volume",
    "source=<slug>-history,target=/home/dev/.history,type=volume"
  ],

  // Les capabilities conservées ne servent qu'à la mise en place décrite plus
  // haut. Un uid non-root a de toute façon un jeu de capabilities effectif vide,
  // et `no-new-privileges` lui interdit de passer root.
  //
  // `no-new-privileges` neutralise `sudo` : aucun outil ne s'ajoute à chaud côté
  // système. Ni SYS_ADMIN ni droit de montage, donc pas de chemin d'évasion
  // connu. C'est aussi ce qui rend le garde-fou root-only réellement
  // inatteignable depuis la session.
  //
  // Rien d'autre dans `runArgs` : le parser d'IntelliJ ne connaît qu'un
  // sous-ensemble des options `docker run` et échoue sur les autres
  // (« ParseException: Unrecognized argument »). Les plafonds CPU/RAM se règlent
  // dans %UserProfile%\.wslconfig.
  "runArgs": [
    "--security-opt", "no-new-privileges",
    "--cap-drop", "ALL",
    "--cap-add", "CHOWN", "--cap-add", "FOWNER", "--cap-add", "DAC_OVERRIDE",
    "--cap-add", "SETUID", "--cap-add", "SETGID"
  ],

  // Un port ouvert sans libellé est illisible dans l'IDE : les deux listes se
  // tiennent à jour ensemble.
  "forwardPorts": [4200, 4000, 8080, 9099],
  "portsAttributes": {
    "4200": { "label": "App Angular" },
    "4000": { "label": "Firebase Emulator UI" },
    "8080": { "label": "Firestore emulator" },
    "9099": { "label": "Auth emulator" }
  },

  // Fourni par l'image. Rien de critique ne passe par le label
  // `devcontainer.metadata` : le support des labels d'image par le plugin
  // devcontainer de JetBrains est incertain, et un postCreateCommand ignoré
  // donnerait une panne silencieuse de tout le provisionnement.
  "postCreateCommand": "/usr/local/share/devcontainer/post-create.sh",

  "customizations": {
    "jetbrains": {
      "backend": "IntelliJ",
      "plugins": ["com.github.l34130.mise"]
    }
  }
}
```

Supprimer ensuite l'ancien emplacement :

```bash
git rm templates/web/devcontainer.json
```

Le test « le template du plugin est conforme » couvre les marques `<slug>` : elles ne sont pas dans les sources de volume vérifiées comme partagées, et `<slug>-cache` passe le contrôle « pas un volume `agent-*` ». Le template est donc valide en tant que tel, ce qui est voulu — il doit rester vérifiable sans substitution.

- [ ] **Step 9: Lancer pour vérifier que tout passe**

Run: `mise run test-unit`
Expected: PASS

Puis vérifier la CLI :

Run: `node tests/lib/check-devcontainer.cjs plugin/skills/onboard-devcontainer/references/devcontainer.template.json`
Expected: `… : conforme`, code de sortie 0

- [ ] **Step 10: Commit**

```bash
git add tests/lib tests/unit plugin/skills/onboard-devcontainer/references/devcontainer.template.json
git rm templates/web/devcontainer.json
git commit -m "Invariants d'un devcontainer.json, template déplacé dans le plugin"
```

---

## Task 2: Le dépôt devient sa propre marketplace

Rend le plugin installable et pose la skill dans son rôle de routeur : détecter le mode, énoncer les règles communes, tenir la liste de contrôle finale. Les quatre modes arrivent aux tâches suivantes.

**Files:**
- Create: `.claude-plugin/marketplace.json`
- Create: `plugin/.claude-plugin/plugin.json`
- Create: `plugin/commands/devcontainer-init.md`
- Create: `plugin/skills/onboard-devcontainer/SKILL.md`
- Create: `tests/unit/plugin-manifests.test.cjs`
- Create: `tests/unit/skill-checklist.test.cjs`

**Interfaces:**
- Consumes: `INVARIANTS` (Task 1), le template (Task 1)
- Produces:
  - marketplace `devcontainer`, plugin `devcontainer` en version `1.1.0`
  - commande `/devcontainer-init`
  - skill `onboard-devcontainer`, dont la section « Détection du mode » rend `brancher`, `migrer`, `amorcer` ou `mettre à jour`, et dont chaque mode lit `references/<mode>.md`

- [ ] **Step 1: Écrire les tests de cohérence des manifestes**

Créer `tests/unit/plugin-manifests.test.cjs` :

```js
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const { parseJsonc } = require('../lib/jsonc.cjs');

const racine = path.join(__dirname, '../..');
const lire = (relatif) => parseJsonc(fs.readFileSync(path.join(racine, relatif), 'utf8'));

const marketplace = () => lire('.claude-plugin/marketplace.json');
const plugin = () => lire('plugin/.claude-plugin/plugin.json');

test('la marketplace déclare le plugin, à une source qui existe', () => {
  const entrees = marketplace().plugins;
  assert.strictEqual(entrees.length, 1);
  const chemin = path.join(racine, '.claude-plugin', entrees[0].source);
  assert.ok(
    fs.existsSync(path.join(chemin, '.claude-plugin/plugin.json')),
    `source introuvable : ${entrees[0].source}`
  );
});

test('le nom du plugin est le même des deux côtés', () => {
  assert.strictEqual(marketplace().plugins[0].name, plugin().name);
});

test('la version est la même des deux côtés', () => {
  assert.strictEqual(marketplace().plugins[0].version, plugin().version);
});

// Le nom de la marketplace n'est pas le chemin du dépôt : `marketplace add`
// prend le second, `plugin install` le premier. Toute ligne de plugins.d qui
// pointe ce dépôt doit donc nommer la marketplace exactement comme elle se
// déclare — sinon le post-create échoue silencieusement, container après
// container.
test('les lignes de plugins.d qui pointent ce dépôt le nomment correctement', () => {
  const fichiers = [
    'images/agent-base/etc/plugins.d/00-base.txt',
    'images/web/etc/plugins.d/10-web.txt',
  ];
  const nomsConnus = new Set([marketplace().name]);
  const pluginsConnus = new Set(marketplace().plugins.map((p) => p.name));

  for (const fichier of fichiers) {
    const lignes = fs.readFileSync(path.join(racine, fichier), 'utf8').split('\n');
    for (const ligne of lignes) {
      const [depot, nomMarketplace, nomPlugin] = ligne.trim().split(/\s+/);
      if (!depot || depot.startsWith('#')) continue;
      if (depot !== 'charlouze/devcontainer') continue;
      assert.ok(nomsConnus.has(nomMarketplace), `marketplace inconnue : ${nomMarketplace}`);
      assert.ok(pluginsConnus.has(nomPlugin), `plugin inconnu : ${nomPlugin}`);
    }
  }
});

// Le plugin est versionné avec les images précisément pour ne jamais poser un
// tag qui n'existe pas.
test("le tag du template suit la majeure de la version du plugin", () => {
  const template = fs.readFileSync(
    path.join(racine, 'plugin/skills/onboard-devcontainer/references/devcontainer.template.json'),
    'utf8'
  );
  const tag = parseJsonc(template).image.split(':')[1];
  assert.strictEqual(tag, plugin().version.split('.')[0]);
});
```

Créer `tests/unit/skill-checklist.test.cjs` :

```js
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const { INVARIANTS } = require('../lib/devcontainer-invariants.cjs');

const SKILL = path.join(__dirname, '../../plugin/skills/onboard-devcontainer/SKILL.md');

// La skill ne peut pas appeler le module d'invariants : elle ne doit rien
// exiger du poste hôte. Sa liste de contrôle est donc une copie en prose, et
// c'est ce test qui empêche les deux de diverger en silence.
test('chaque invariant figure dans la liste de contrôle de la skill', () => {
  const skill = fs.readFileSync(SKILL, 'utf8');
  for (const { id } of INVARIANTS) {
    assert.ok(skill.includes(`\`${id}\``), `invariant absent de SKILL.md : ${id}`);
  }
});

test('la skill a un frontmatter avec name et description', () => {
  const skill = fs.readFileSync(SKILL, 'utf8');
  const frontmatter = skill.match(/^---\n([\s\S]*?)\n---/);
  assert.ok(frontmatter, 'frontmatter absent');
  assert.match(frontmatter[1], /^name: onboard-devcontainer$/m);
  assert.match(frontmatter[1], /^description: .{20,}$/m);
});

test('la skill renvoie vers un fichier de référence par mode', () => {
  const skill = fs.readFileSync(SKILL, 'utf8');
  const dossier = path.dirname(SKILL);
  for (const mode of ['brancher', 'migrer', 'amorcer', 'mettre-a-jour']) {
    assert.ok(skill.includes(`references/${mode}.md`), `mode non routé : ${mode}`);
    assert.ok(
      fs.existsSync(path.join(dossier, 'references', `${mode}.md`)),
      `référence absente : ${mode}.md`
    );
  }
});
```

- [ ] **Step 2: Lancer pour vérifier l'échec**

Run: `mise run test-unit`
Expected: FAIL — `ENOENT` sur `.claude-plugin/marketplace.json`

- [ ] **Step 3: Écrire les manifestes**

Créer `.claude-plugin/marketplace.json` :

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "devcontainer",
  "description": "Dev containers durcis pour agents autonomes, et l'onboarding des dépôts qui les utilisent",
  "owner": {
    "name": "Charlouze",
    "email": "me@charlouze.com"
  },
  "plugins": [
    {
      "name": "devcontainer",
      "description": "Branche, migre, amorce ou met à jour le dev container d'un dépôt sur les images ghcr.io/charlouze/devcontainer-*",
      "version": "1.1.0",
      "source": "../plugin"
    }
  ]
}
```

Créer `plugin/.claude-plugin/plugin.json` :

```json
{
  "name": "devcontainer",
  "description": "Branche, migre, amorce ou met à jour le dev container d'un dépôt sur les images ghcr.io/charlouze/devcontainer-*",
  "version": "1.1.0",
  "author": { "name": "Charlouze" },
  "homepage": "https://github.com/charlouze/devcontainer",
  "repository": "https://github.com/charlouze/devcontainer",
  "keywords": ["devcontainer", "docker", "sandbox", "firebase", "nx"]
}
```

- [ ] **Step 4: Écrire la commande**

Créer `plugin/commands/devcontainer-init.md` :

```markdown
---
description: Branche, migre, amorce ou met à jour le dev container de ce dépôt
argument-hint: "[chemin du dépôt — par défaut, le répertoire courant]"
---

Invoque la skill `devcontainer:onboard-devcontainer` et suis-la à la lettre.

Dépôt à traiter : $ARGUMENTS — si l'argument est vide, le répertoire courant.

Ne devine pas le mode toi-même : la skill le détermine à partir de ce que le
dépôt contient, et le mode détermine tout le reste.
```

- [ ] **Step 5: Écrire la skill**

Créer `plugin/skills/onboard-devcontainer/SKILL.md` :

```markdown
---
name: onboard-devcontainer
description: À utiliser quand un dépôt doit recevoir un dev container, quand une configuration de dev container existante doit passer sur les images partagées ghcr.io/charlouze/devcontainer-*, quand un dépôt vide doit être amorcé, ou quand un dépôt déjà branché doit suivre une nouvelle version des images — notamment après /devcontainer-init.
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
- **Rien n'est supprimé ni écrasé sans que le diff ait été montré** et validé.
  Vaut pour les fichiers comme pour les clés d'un fichier existant.
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
```

- [ ] **Step 6: Créer les quatre références en placeholder pour que le routage tienne**

Les tâches 3 à 6 écrivent ces fichiers. Pour que `tests/unit/skill-checklist.test.cjs` passe dès maintenant sans mentir sur leur contenu, créer les quatre — `brancher.md`, `migrer.md`, `amorcer.md`, `mettre-a-jour.md` — dans `plugin/skills/onboard-devcontainer/references/`, chacun avec ces deux lignes, le titre reprenant le nom du mode :

```markdown
# Mode « brancher »

Non encore écrit. Arrête-toi et dis-le : ce mode n'est pas disponible.
```

Un mode qui refuse est acceptable ; un mode qui improvise ne l'est pas.

- [ ] **Step 7: Lancer les tests**

Run: `mise run test-unit`
Expected: PASS

- [ ] **Step 8: Installer le plugin depuis la copie de travail et vérifier qu'il apparaît**

```bash
claude plugin marketplace add .
claude plugin install devcontainer@devcontainer
claude plugin details devcontainer@devcontainer
```

Expected: le plugin est listé comme installé, et `/devcontainer-init` apparaît dans une session ouverte sur ce dépôt.

Si `marketplace add .` refuse un chemin local, utiliser le chemin absolu du
dépôt. Consigner ce qui a marché : c'est aussi la procédure de test des tâches
suivantes.

- [ ] **Step 9: Commit**

```bash
git add .claude-plugin plugin tests/unit
git commit -m "Le dépôt devient sa propre marketplace, squelette du plugin d'onboarding"
```

---

## Task 3: Mode « brancher »

Le cas le plus courant : un dépôt qui a du code et pas de `.devcontainer`.

**Files:**
- Modify: `plugin/skills/onboard-devcontainer/references/brancher.md`
- Create: `tests/fixtures/onboarding/brancher/mon-appli/` (dépôt d'entrée)
- Create: `tests/fixtures/onboarding/brancher/attendu/devcontainer.json`
- Create: `tests/fixtures/onboarding/brancher/attendu/mise-fragment.toml`
- Create: `tests/unit/fixtures-onboarding.test.cjs`

**Interfaces:**
- Consumes: `SKILL.md` (routage), le template
- Produces: `references/brancher.md`, et la première fixture — dont la forme (`<cas>/<dépôt>/` + `<cas>/attendu/`) est reprise par les trois modes suivants

- [ ] **Step 1: Écrire la fixture d'entrée**

Créer `tests/fixtures/onboarding/brancher/mon-appli/package.json` :

```json
{
  "name": "mon-appli",
  "version": "0.0.0",
  "devDependencies": {
    "@playwright/test": "^1.54.0",
    "nx": "^21.0.0"
  }
}
```

Créer `tests/fixtures/onboarding/brancher/mon-appli/firebase.json` — le port
Firestore est volontairement déplacé, pour que la fixture prouve que la section
`emulators` fait autorité sur les ports par défaut :

```json
{
  "hosting": {
    "public": "dist/apps/mon-appli/browser"
  },
  "firestore": {
    "rules": "firestore.rules"
  },
  "emulators": {
    "ui": { "enabled": true, "host": "0.0.0.0" },
    "auth": { "host": "0.0.0.0", "port": 9099 },
    "firestore": { "host": "0.0.0.0", "port": 8081 }
  }
}
```

Créer `tests/fixtures/onboarding/brancher/mon-appli/.firebaserc` :

```json
{
  "projects": {
    "default": "mon-appli-dev"
  }
}
```

Créer `tests/fixtures/onboarding/brancher/mon-appli/angular.json` — port de
serve déplacé lui aussi :

```json
{
  "version": 1,
  "projects": {
    "mon-appli": {
      "projectType": "application",
      "architect": {
        "serve": {
          "builder": "@angular/build:dev-server",
          "options": { "port": 4300 }
        }
      }
    }
  }
}
```

Créer `tests/fixtures/onboarding/brancher/mon-appli/mise.toml` — il a déjà une
tâche `install`, mais pas de `setup` :

```toml
[tools]
node = "22"
pnpm = "latest"

[tasks.install]
description = "Installe les dépendances"
run = "pnpm install --frozen-lockfile"
```

- [ ] **Step 2: Écrire la sortie attendue**

Créer `tests/fixtures/onboarding/brancher/attendu/devcontainer.json` : le
template, marques substituées. Les commentaires du template sont conservés — ils
sont omis ici pour la lisibilité du plan, mais le fichier de la fixture les
porte, à l'identique du template :

```json
{
  "name": "mon-appli (agent sandbox)",
  "image": "ghcr.io/charlouze/devcontainer-web:1",

  "containerUser": "root",
  "remoteUser": "dev",

  "containerEnv": {
    "FIRESTORE_EMULATOR_HOST": "127.0.0.1:8081",
    "FIREBASE_AUTH_EMULATOR_HOST": "127.0.0.1:9099",
    "GCLOUD_PROJECT": "mon-appli-dev",
    "GOOGLE_CLOUD_PROJECT": "mon-appli-dev"
  },

  "mounts": [
    "source=agent-claude,target=/home/dev/.claude,type=volume",
    "source=mon-appli-cache,target=/home/dev/.cache,type=volume",
    "source=agent-pnpm-store,target=/home/dev/.cache/pnpm-store,type=volume",
    "source=agent-playwright,target=/home/dev/.cache/ms-playwright,type=volume",
    "source=mon-appli-history,target=/home/dev/.history,type=volume"
  ],

  "runArgs": [
    "--security-opt", "no-new-privileges",
    "--cap-drop", "ALL",
    "--cap-add", "CHOWN", "--cap-add", "FOWNER", "--cap-add", "DAC_OVERRIDE",
    "--cap-add", "SETUID", "--cap-add", "SETGID"
  ],

  "forwardPorts": [4300, 4000, 8081, 9099],
  "portsAttributes": {
    "4300": { "label": "App Angular" },
    "4000": { "label": "Firebase Emulator UI" },
    "8081": { "label": "Firestore emulator" },
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

Créer `tests/fixtures/onboarding/brancher/attendu/mise-fragment.toml` — ce qui
doit être ajouté au `mise.toml` du dépôt, et rien d'autre :

```toml
[tasks.setup]
description = "Provisionnement du dev container"
run = """
mise run install
pnpm exec playwright install chromium webkit
"""
```

- [ ] **Step 3: Écrire le test des fixtures**

Créer `tests/unit/fixtures-onboarding.test.cjs` :

```js
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const { verifier } = require('../lib/devcontainer-invariants.cjs');

const FIXTURES = path.join(__dirname, '../fixtures/onboarding');

// Les fixtures sont l'oracle du rejeu manuel de la skill. Si une sortie
// attendue viole elle-même un invariant, le rejeu validerait une régression.
test('chaque sortie attendue respecte les invariants', () => {
  const cas = fs.readdirSync(FIXTURES, { withFileTypes: true }).filter((e) => e.isDirectory());
  assert.ok(cas.length > 0, 'aucune fixture');

  for (const entree of cas) {
    const fichier = path.join(FIXTURES, entree.name, 'attendu/devcontainer.json');
    if (!fs.existsSync(fichier)) continue;
    assert.deepStrictEqual(
      verifier(fs.readFileSync(fichier, 'utf8')),
      [],
      `fixture non conforme : ${entree.name}`
    );
  }
});

// Les commentaires du template sont un livrable : une sortie attendue qui les
// aurait perdus entérinerait leur perte.
test('chaque sortie attendue conserve les commentaires du template', () => {
  const cas = fs.readdirSync(FIXTURES, { withFileTypes: true }).filter((e) => e.isDirectory());
  for (const entree of cas) {
    const fichier = path.join(FIXTURES, entree.name, 'attendu/devcontainer.json');
    if (!fs.existsSync(fichier)) continue;
    const texte = fs.readFileSync(fichier, 'utf8');
    assert.match(texte, /no-new-privileges. neutralise/, `commentaires perdus : ${entree.name}`);
    assert.match(texte, /parser d'IntelliJ/, `commentaires perdus : ${entree.name}`);
  }
});
```

- [ ] **Step 4: Lancer pour vérifier l'échec**

Run: `mise run test-unit`
Expected: FAIL — la sortie attendue de `brancher` ne porte pas encore les commentaires du template

- [ ] **Step 5: Reporter les commentaires du template dans la sortie attendue**

Recopier dans `tests/fixtures/onboarding/brancher/attendu/devcontainer.json` les
blocs de commentaires du template, aux mêmes emplacements.

Run: `mise run test-unit`
Expected: PASS

- [ ] **Step 6: Écrire le mode**

Écrire `plugin/skills/onboard-devcontainer/references/brancher.md` :

````markdown
# Mode « brancher »

Le dépôt a du code et pas de `.devcontainer/`. Tout ce qu'il faut savoir est
déjà dans le dépôt : lis-le, n'interroge pas l'humain.

## 1. Lire le dépôt

**`firebase.json`** — si une section `emulators` existe, **elle fait autorité**,
y compris pour un port déplacé. Chaque émulateur qui y figure est à ouvrir.
Sinon, prends les clés produits de premier niveau (`firestore`, `functions`,
`hosting`, `storage`, `database`) et donne à chacune son port par défaut.
L'émulateur UI n'a pas de clé produit : ouvre son port dès qu'il y a des
émulateurs.

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

**`angular.json`, `nx.json`, `project.json`** — le port de serve se lit dans la
cible `serve`, clé `options.port`. À défaut, 4200.

**`package.json`** — la présence de `@playwright/test` décide de la ligne
Playwright de la tâche `setup`, et de rien d'autre.

## 2. Écrire `.devcontainer/devcontainer.json`

Pars de `references/devcontainer.template.json`, garde ses commentaires, et
remplace :

- `<Nom du projet>` — le nom du dépôt tel qu'un humain l'écrit ;
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
````

- [ ] **Step 7: Rejouer la skill sur la fixture**

```bash
cp -r tests/fixtures/onboarding/brancher/mon-appli /tmp/essai-brancher
```

Dans une session Claude Code ouverte sur `/tmp/essai-brancher`, lancer
`/devcontainer-init`. Puis :

```bash
diff -u tests/fixtures/onboarding/brancher/attendu/devcontainer.json \
        /tmp/essai-brancher/.devcontainer/devcontainer.json
node tests/lib/check-devcontainer.cjs /tmp/essai-brancher/.devcontainer/devcontainer.json
grep -A6 'tasks.setup' /tmp/essai-brancher/mise.toml
```

Expected: aucune différence hors reformulation du champ `name` ; `conforme` ;
la tâche `setup` correspond à `attendu/mise-fragment.toml`.

Si le diff porte sur autre chose que le `name`, ce n'est pas la fixture qu'on
corrige : c'est `brancher.md` qui manque de précision à l'endroit exact où
l'écart est apparu.

- [ ] **Step 8: Commit**

```bash
git add plugin/skills/onboard-devcontainer/references/brancher.md tests/fixtures tests/unit
git commit -m "Mode « brancher » du plugin d'onboarding"
```

---

## Task 4: Mode « migrer »

Un dépôt qui porte déjà sa propre configuration de dev container — le cas de
Compte-de-Famille, et celui où l'on peut détruire du travail.

**Files:**
- Modify: `plugin/skills/onboard-devcontainer/references/migrer.md`
- Create: `tests/fixtures/onboarding/migrer/compte-de-famille/`
- Create: `tests/fixtures/onboarding/migrer/attendu/devcontainer.json`
- Create: `tests/fixtures/onboarding/migrer/attendu/suppressions.txt`

**Interfaces:**
- Consumes: `SKILL.md`, le template, la forme de fixture de la Task 3
- Produces: `references/migrer.md`

- [ ] **Step 1: Écrire la fixture d'entrée**

Recopier la configuration réelle d'avant la base partagée :

```bash
mkdir -p tests/fixtures/onboarding/migrer/compte-de-famille/.devcontainer
cp ../Compte-de-Famille/.devcontainer/devcontainer.json \
   tests/fixtures/onboarding/migrer/compte-de-famille/.devcontainer/
cp ../Compte-de-Famille/firebase.json ../Compte-de-Famille/.firebaserc \
   tests/fixtures/onboarding/migrer/compte-de-famille/
```

Les quatre fichiers rendus inutiles par l'image n'ont pas besoin d'être réels :
seule leur présence compte pour la détection. Les créer en marqueurs :

```bash
cd tests/fixtures/onboarding/migrer/compte-de-famille/.devcontainer
for f in Dockerfile post-create.sh agent-guard.cjs managed-settings.json; do
  printf '# fixture : contenu sans importance, seule la présence compte\n' > "$f"
done
cd -
```

Ajouter `tests/fixtures/onboarding/migrer/compte-de-famille/mise.toml` :

```toml
[tools]
node = "22"
pnpm = "latest"

[tasks.node-install]
description = "Installe les packages nodes"
run = "pnpm install"

[tasks.install]
description = "Install les packages et les skills"
run = { tasks = ["node-install"] }

[tasks.emulators]
description = "Démarrer les émulateurs Firebase"
tools.java = "25"
run = "pnpm exec firebase emulators:start"
```

- [ ] **Step 2: Écrire la sortie attendue**

Créer `tests/fixtures/onboarding/migrer/attendu/devcontainer.json` : le template,
commentaires compris, avec exactement ces substitutions —

- `name` : `"Compte-de-Famille (agent sandbox)"` ;
- `image` : inchangée par rapport au template (`…devcontainer-web:1`) ;
- `containerEnv` : `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080`,
  `FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099`,
  `GCLOUD_PROJECT` et `GOOGLE_CLOUD_PROJECT` à `compte-de-famille-dev`. **Pas**
  de `CDF_SANDBOX` : le garde-fou s'active désormais sur un marqueur root-only,
  et la recopier serait un mensonge sur ce qui protège le container ;
- `mounts` : `compte-de-famille-cache` et `compte-de-famille-history`, les trois
  autres sources inchangées ;
- `forwardPorts` : `[4200, 4000, 8080, 9099]` avec les quatre libellés du
  template (« App Angular », « Firebase Emulator UI », « Firestore emulator »,
  « Auth emulator ») ;
- `runArgs`, `postCreateCommand`, `customizations` : inchangés.

Créer `tests/fixtures/onboarding/migrer/attendu/suppressions.txt` — la liste
exacte de ce qui devient inutile, à montrer avant toute suppression :

```
.devcontainer/Dockerfile
.devcontainer/agent-guard.cjs
.devcontainer/managed-settings.json
.devcontainer/post-create.sh
```

- [ ] **Step 3: Lancer les tests**

Run: `mise run test-unit`
Expected: PASS — la nouvelle sortie attendue est prise par `fixtures-onboarding.test.cjs`

Si elle échoue sur `pas-de-variable-garde-fou`, c'est que `CDF_SANDBOX` a été
recopiée : c'est exactement ce que le test doit attraper.

- [ ] **Step 4: Écrire le mode**

Écrire `plugin/skills/onboard-devcontainer/references/migrer.md` :

````markdown
# Mode « migrer »

Le dépôt porte sa propre configuration de dev container. C'est le mode qui peut
détruire du travail : **rien n'est supprimé avant que le diff ait été montré et
validé.**

## 1. Extraire ce qui appartient réellement au projet

Du `devcontainer.json` existant, ne garde que :

- le nom lisible du projet ;
- les ports (`forwardPorts`, `portsAttributes`) ;
- les variables d'émulateur et l'identifiant de projet Firebase ;
- toute personnalisation d'IDE propre au projet.

Tout le reste vient désormais de l'image. En particulier, ne recopie **jamais** :

- une variable qui prétendait activer le garde-fou (`CDF_SANDBOX` et
  apparentées) — il s'active maintenant sur `/etc/claude-guard/enabled`, root et
  non falsifiable, et la variable n'aurait plus aucun effet ;
- un `build`/`dockerFile` — l'image remplace le Dockerfile ;
- un `postCreateCommand` pointant dans le workspace ;
- des `runArgs` supplémentaires : le parser d'IntelliJ échoue sur ce qu'il ne
  connaît pas, et le template porte déjà ce qu'il faut.

Si l'ancien fichier portait un réglage que tu ne sais pas classer, **demande**
plutôt que de trancher.

## 2. Écrire la version courte

Pars de `references/devcontainer.template.json` comme au mode « brancher »,
avec les valeurs extraites ci-dessus.

## 3. Les volumes changent de nom

C'est la conséquence à annoncer explicitement, parce qu'elle a un effet visible :

- le volume de login devient `agent-claude`, partagé entre projets. Si l'ancien
  était propre au projet, **le login de l'agent est à refaire une fois** ;
- l'ancien volume de cache reste sur le disque et n'est plus monté. Il n'est pas
  supprimé : c'est à l'humain de décider quand.

Liste les anciens volumes et donne la commande pour les retirer plus tard, sans
la lancer :

```bash
docker volume ls --filter name=<ancien-prefixe>
docker volume rm <volume>
```

## 4. Signaler les fichiers devenus inutiles

L'image fournit désormais le Dockerfile, le provisionnement, le garde-fou et ses
managed settings. Dans `.devcontainer/`, deviennent inutiles :

- `Dockerfile`
- `post-create.sh`
- `agent-guard.cjs` (et tout module de règles qui l'accompagne)
- `managed-settings.json`

Montre la liste, montre le diff, demande. Ne supprime que ce qui a été validé.
Si l'un de ces fichiers contenait des règles de garde-fou propres au projet,
elles ne se perdent pas : elles se réécrivent en
`.devcontainer/guard-rules.json`, qui **ajoute** au socle.

```json
{
  "bash":  [{ "pattern": "\\bstripe\\s+", "flags": "i", "reason": "…" }],
  "paths": [{ "pattern": "fixtures/prod-.*\\.json$", "reason": "…" }]
}
```

Un `README.md` de `.devcontainer/` se réduit à ce qui est propre au projet, le
reste renvoyant à `https://github.com/charlouze/devcontainer`.

## 5. La tâche `setup`

Comme au mode « brancher » : ce que faisait l'ancien `post-create.sh` **au titre
du projet** — et lui seul — devient la tâche `setup` du `mise.toml`. Ce qu'il
faisait au titre de l'environnement (mise, pnpm, plugins, réglages de l'agent)
est déjà fait par l'image : ne le recopie pas.

## 6. Terminer

Repasse la liste de contrôle finale de `SKILL.md`. Annonce qu'aucun changement
fonctionnel n'est attendu côté développeur — mêmes ports, mêmes tâches, mêmes
garde-fous — et que la première ouverture reconstruira le container.
````

- [ ] **Step 5: Rejouer la skill sur la fixture**

```bash
cp -r tests/fixtures/onboarding/migrer/compte-de-famille /tmp/essai-migrer
```

Session sur `/tmp/essai-migrer`, `/devcontainer-init`. Puis :

```bash
diff -u tests/fixtures/onboarding/migrer/attendu/devcontainer.json \
        /tmp/essai-migrer/.devcontainer/devcontainer.json
node tests/lib/check-devcontainer.cjs /tmp/essai-migrer/.devcontainer/devcontainer.json
```

Expected: aucune différence hors le champ `name` ; `conforme` ; la skill a
**demandé** avant de supprimer, et a nommé exactement les quatre fichiers de
`attendu/suppressions.txt`.

Vérifier aussi le cas de refus : rejouer en répondant « non » à la suppression,
et constater que les quatre fichiers sont toujours là.

- [ ] **Step 6: Commit**

```bash
git add plugin/skills/onboard-devcontainer/references/migrer.md tests/fixtures
git commit -m "Mode « migrer » du plugin d'onboarding"
```

---

## Task 5: Mode « amorcer »

Le seul mode qui interroge l'humain, et le seul où l'ordre s'inverse : le
container vient d'abord, le projet naît dedans.

**Files:**
- Modify: `plugin/skills/onboard-devcontainer/references/amorcer.md`
- Create: `tests/fixtures/onboarding/amorcer/nouveau-projet/.gitkeep`
- Create: `tests/fixtures/onboarding/amorcer/attendu/devcontainer.json`

**Interfaces:**
- Consumes: `SKILL.md`, le template
- Produces: `references/amorcer.md`

- [ ] **Step 1: Écrire la fixture**

```bash
mkdir -p tests/fixtures/onboarding/amorcer/nouveau-projet
touch tests/fixtures/onboarding/amorcer/nouveau-projet/.gitkeep
```

Créer `tests/fixtures/onboarding/amorcer/attendu/devcontainer.json` : le
template, commentaires compris, avec la sélection par défaut (UI, Auth,
Firestore), slug `nouveau-projet`, identifiant `demo-nouveau-projet`, port de
serve conventionnel 4200 :

- `containerEnv` : `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080`,
  `FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099`,
  `GCLOUD_PROJECT` et `GOOGLE_CLOUD_PROJECT` à `demo-nouveau-projet` ;
- `forwardPorts` : `[4200, 4000, 8080, 9099]`, avec les quatre libellés ;
- `mounts` : `nouveau-projet-cache` et `nouveau-projet-history`.

- [ ] **Step 2: Lancer les tests**

Run: `mise run test-unit`
Expected: PASS

- [ ] **Step 3: Écrire le mode**

Écrire `plugin/skills/onboard-devcontainer/references/amorcer.md` :

```markdown
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
```

- [ ] **Step 4: Rejouer la skill sur la fixture**

```bash
cp -r tests/fixtures/onboarding/amorcer/nouveau-projet /tmp/essai-amorcer
```

Session sur `/tmp/essai-amorcer`, `/devcontainer-init`, répondre en gardant la
sélection par défaut. Puis :

```bash
diff -u tests/fixtures/onboarding/amorcer/attendu/devcontainer.json \
        /tmp/essai-amorcer/.devcontainer/devcontainer.json
ls /tmp/essai-amorcer
```

Expected: aucune différence hors le champ `name` ; **aucun** `mise.toml` créé ;
la question a bien été posée avec UI, Auth et Firestore pré-cochés.

Rejouer une seconde fois en cochant en plus Storage, et vérifier que le port
9199, son libellé et `FIREBASE_STORAGE_EMULATOR_HOST` apparaissent tous les trois.

- [ ] **Step 5: Commit**

```bash
git add plugin/skills/onboard-devcontainer/references/amorcer.md tests/fixtures
git commit -m "Mode « amorcer » du plugin d'onboarding"
```

---

## Task 6: Mode « mettre à jour »

Le mode qui justifie l'outil plus que le premier branchement : quand la base
passe en `2`, il faut repasser sur chaque dépôt.

**Files:**
- Modify: `plugin/skills/onboard-devcontainer/references/mettre-a-jour.md`
- Create: `tests/fixtures/onboarding/mettre-a-jour/vieux-projet/`
- Create: `tests/fixtures/onboarding/mettre-a-jour/attendu/devcontainer.json`
- Create: `tests/fixtures/onboarding/mettre-a-jour/attendu/ecarts.md`

**Interfaces:**
- Consumes: `SKILL.md`, le template
- Produces: `references/mettre-a-jour.md`

- [ ] **Step 1: Écrire la fixture d'entrée**

Créer `tests/fixtures/onboarding/mettre-a-jour/vieux-projet/.devcontainer/devcontainer.json` —
un dépôt déjà branché, mais sur une forme antérieure : le montage
`agent-playwright` manque, un port est ouvert sans libellé, et les commentaires
ont été perdus :

```json
{
  "name": "vieux-projet (agent sandbox)",
  "image": "ghcr.io/charlouze/devcontainer-web:1",

  "containerUser": "root",
  "remoteUser": "dev",

  "containerEnv": {
    "FIRESTORE_EMULATOR_HOST": "127.0.0.1:8080",
    "GCLOUD_PROJECT": "vieux-projet-dev",
    "GOOGLE_CLOUD_PROJECT": "vieux-projet-dev"
  },

  "mounts": [
    "source=agent-claude,target=/home/dev/.claude,type=volume",
    "source=vieux-projet-cache,target=/home/dev/.cache,type=volume",
    "source=agent-pnpm-store,target=/home/dev/.cache/pnpm-store,type=volume",
    "source=vieux-projet-history,target=/home/dev/.history,type=volume"
  ],

  "runArgs": [
    "--security-opt", "no-new-privileges",
    "--cap-drop", "ALL",
    "--cap-add", "CHOWN", "--cap-add", "FOWNER", "--cap-add", "DAC_OVERRIDE",
    "--cap-add", "SETUID", "--cap-add", "SETGID"
  ],

  "forwardPorts": [4200, 8080],
  "portsAttributes": {
    "4200": { "label": "App Angular" }
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

Ajouter un `mise.toml` avec une tâche `setup` déjà en place, pour vérifier
qu'elle n'est pas réécrite :

```toml
[tasks.setup]
description = "Provisionnement du dev container"
run = "pnpm install --frozen-lockfile"
```

- [ ] **Step 2: Écrire la sortie attendue**

Créer `tests/fixtures/onboarding/mettre-a-jour/attendu/devcontainer.json` : le
fichier ci-dessus, corrigé — montage `agent-playwright` ajouté à sa place,
libellé « Firestore emulator » ajouté pour 8080, commentaires du template
rétablis, valeurs propres au projet inchangées.

Créer `tests/fixtures/onboarding/mettre-a-jour/attendu/ecarts.md` — ce que la
skill doit avoir rapporté :

```markdown
- montage `agent-playwright` absent : les navigateurs seraient retéléchargés à
  chaque rebuild du container
- port 8080 ouvert sans libellé
- commentaires du template absents
- tag d'image : `1`, déjà à jour
```

- [ ] **Step 3: Lancer les tests**

Run: `mise run test-unit`
Expected: PASS

Noter que la fixture **d'entrée** viole deux invariants (`volumes`,
`ports-libelles`) : c'est voulu, et le test ne vérifie que les `attendu/`.

- [ ] **Step 4: Écrire le mode**

Écrire `plugin/skills/onboard-devcontainer/references/mettre-a-jour.md` :

```markdown
# Mode « mettre à jour »

Le dépôt est déjà branché sur les images du dépôt. C'est le mode le plus
fréquent dans la durée : quand la base passe une majeure, il faut repasser sur
chaque projet.

## 1. Le tag

Le tag de référence est celui de `references/devcontainer.template.json`, et
lui seul. Le plugin est versionné avec les images : ce tag existe forcément,
celui que tu inventerais, non.

- même majeure que le fichier du dépôt → rien à faire côté tag ;
- majeure supérieure → aligne le fichier, et **annonce-le comme un changement de
  majeure** : dis ce qui change, et propose de lire les notes de version plutôt
  que de faire le saut à l'aveugle.

## 2. Les écarts avec le template

Compare le fichier du dépôt au template, clé par clé, et **rapporte** :

- une clé du template absente du fichier — typiquement un montage ajouté depuis
  la dernière fois ;
- une clé du template dont la valeur diffère **sans raison propre au projet** :
  `containerUser`, `remoteUser`, `postCreateCommand`, `runArgs`, et les sources
  des volumes partagés `agent-*` ;
- les commentaires du template qui manquent ;
- un port de `forwardPorts` sans libellé.

Ne rapporte pas comme écart ce qui appartient légitimement au projet : `name`,
`containerEnv`, la liste des ports, les sources de volumes préfixées par le
slug, les personnalisations d'IDE.

## 3. Corriger

Applique les corrections, montre le diff, et laisse à l'humain la décision sur
tout ce qui touche à une valeur propre au projet. Les écarts sur le
durcissement, eux, se corrigent : un `devcontainer.json` qui a perdu
`no-new-privileges` ou `--cap-drop ALL` n'est pas une variante locale, c'est une
régression.

## 4. Le reste du dépôt

- Si le `mise.toml` n'a pas de tâche `setup`, ajoute-la comme au mode
  « brancher ». Si elle existe, **n'y touche pas** : c'est le projet qui la tient.
- Si des émulateurs ont été ajoutés au `firebase.json` depuis le branchement,
  leurs ports et variables manquent probablement : applique les mêmes règles de
  lecture qu'au mode « brancher ».
- Si `.devcontainer/` contient encore un `Dockerfile`, un `post-create.sh`, un
  `agent-guard.cjs` ou un `managed-settings.json`, le dépôt est en fait à moitié
  migré : bascule sur `references/migrer.md` et dis-le.

## 5. Terminer

Repasse la liste de contrôle finale de `SKILL.md`. Si le tag a changé de majeure,
rappelle que la prochaine ouverture reconstruira le container.
```

- [ ] **Step 5: Rejouer la skill sur la fixture**

```bash
cp -r tests/fixtures/onboarding/mettre-a-jour/vieux-projet /tmp/essai-maj
```

Session sur `/tmp/essai-maj`, `/devcontainer-init`. Puis :

```bash
diff -u tests/fixtures/onboarding/mettre-a-jour/attendu/devcontainer.json \
        /tmp/essai-maj/.devcontainer/devcontainer.json
node tests/lib/check-devcontainer.cjs /tmp/essai-maj/.devcontainer/devcontainer.json
cat /tmp/essai-maj/mise.toml
```

Expected: aucune différence ; `conforme` ; le `mise.toml` est **inchangé** ; les
écarts rapportés couvrent les quatre points de `attendu/ecarts.md`.

- [ ] **Step 6: Commit**

```bash
git add plugin/skills/onboard-devcontainer/references/mettre-a-jour.md tests/fixtures
git commit -m "Mode « mettre à jour » du plugin d'onboarding"
```

---

## Task 7: Installation dans les images, documentation et publication

Referme les deux dettes du plan précédent : la ligne `plugins.d` laissée de côté
faute de plugin, et la vérification jamais faite de `claude plugin install` en
non-interactif.

**Files:**
- Modify: `images/agent-base/etc/plugins.d/00-base.txt`
- Modify: `README.md`
- Modify: `.github/workflows/publish.yml`
- Test: `mise run check`

**Interfaces:**
- Consumes: tout ce qui précède
- Produces: images `1.1.0` publiées, plugin installé d'office dans tout container

- [ ] **Step 1: Déclarer le plugin dans la couche base**

Modifier `images/agent-base/etc/plugins.d/00-base.txt` :

```
# <dépôt-marketplace>                <nom-marketplace>        <plugin>
anthropics/claude-plugins-official   claude-plugins-official  superpowers
charlouze/devcontainer               devcontainer             devcontainer
```

Le test `plugin-manifests.test.cjs` de la Task 2 vérifie désormais cette ligne
pour de bon : `charlouze/devcontainer` est le chemin du dépôt, `devcontainer` le
nom déclaré dans `marketplace.json`, et `devcontainer` le nom du plugin.

Run: `mise run test-unit`
Expected: PASS

- [ ] **Step 2: Reconstruire et rejouer le smoke test**

Run: `mise run check`
Expected: PASS — le smoke test utilise un `claude` bouchonné, donc il valide le
format de la ligne et l'enchaînement, pas l'installation réelle. Celle-ci est
l'objet du Step 5.

- [ ] **Step 3: Mettre le README à jour**

Dans `README.md` :

- remplacer la section « Brancher un projet » par le passage par le plugin :

````markdown
## Brancher un projet

```bash
claude plugin marketplace add charlouze/devcontainer
claude plugin install devcontainer@devcontainer
```

Puis, dans le dépôt à brancher :

```
/devcontainer-init
```

Un seul point d'entrée, quatre modes déduits de ce que le dépôt contient :

| Le dépôt… | Mode |
|---|---|
| a du code, pas de `.devcontainer` | brancher |
| a son propre `.devcontainer` d'avant ces images | migrer |
| est vide | amorcer — le container vient d'abord, le projet naît dedans |
| est déjà branché | mettre à jour |

Le plugin est aussi installé d'office dans les containers, mais il est fait pour
être installé **sur le poste** : il doit pouvoir agir avant que le container
existe.

Pour brancher un dépôt à la main, le fichier de référence est
`plugin/skills/onboard-devcontainer/references/devcontainer.template.json` — ses
commentaires font partie du livrable. Il reste à ajouter une tâche `setup` au
`mise.toml` du projet : c'est le contrat entre l'image et le projet.

```toml
[tasks.setup]
description = "Provisionnement du projet"
run = "pnpm install --frozen-lockfile"
```
````

- ajouter à la section « Publier une version » la mise à jour du plugin :

````markdown
Avant de taguer, aligner la version du plugin sur celle des images, dans
`.claude-plugin/marketplace.json` et `plugin/.claude-plugin/plugin.json`. Sur un
changement de majeure, mettre aussi à jour le tag du template
(`plugin/skills/onboard-devcontainer/references/devcontainer.template.json`) :
`tests/unit/plugin-manifests.test.cjs` échoue tant que les deux divergent.
````

- [ ] **Step 4: Faire tourner les tests unitaires en CI sur le plugin**

Le job `publish.yml` lance déjà `node --test tests/unit/`. Vérifier que le motif
couvre bien les nouveaux fichiers ; sinon l'aligner sur celui du `mise.toml` :

```yaml
      - name: Tests unitaires
        run: node --test "tests/unit/**/*.test.cjs"
```

- [ ] **Step 5: Vérifier `claude plugin install` en non-interactif, dans un vrai container**

Le point n°4 laissé ouvert par le plan précédent. Dans un container construit
localement, après login :

```bash
docker run --rm -it -v agent-claude:/home/dev/.claude -u dev devcontainer-web:dev bash -lc '
  claude plugin marketplace add anthropics/claude-plugins-official
  claude plugin marketplace add pbakaus/impeccable
  claude plugin marketplace add charlouze/devcontainer
  claude plugin install superpowers@claude-plugins-official
  claude plugin install impeccable@impeccable
  claude plugin install devcontainer@devcontainer
  for p in superpowers@claude-plugins-official impeccable@impeccable devcontainer@devcontainer; do
    claude plugin details "$p" >/dev/null && echo "ok   $p" || echo "KO   $p"
  done'
```

Expected: `ok` sur les trois.

Si l'un échoue faute d'interactivité, ce n'est pas `install-plugins.sh` qu'on
corrige d'abord : c'est la cause qu'on cherche (authentification requise, prompt
de confirmation, marketplace non résolue). Le script avertit déjà en nommant la
commande à rejouer — c'est le repli acceptable, pas la solution.

- [ ] **Step 6: Commit et publication**

```bash
git add images/agent-base/etc/plugins.d/00-base.txt README.md .github/workflows/publish.yml
git commit -m "Plugin d'onboarding installé d'office, documentation et publication"
git tag v1.1.0
git push origin main --tags
```

Vérifier ensuite, depuis un poste propre :

```bash
claude plugin marketplace add charlouze/devcontainer
claude plugin install devcontainer@devcontainer
```

Expected: `/devcontainer-init` disponible sans avoir cloné le dépôt.

---

## Points à vérifier pendant l'exécution

1. **`marketplace add` sur un chemin local** (Task 2, Step 8). Si la commande
   n'accepte qu'un dépôt distant, tester le plugin en poussant une branche et en
   ajoutant la marketplace par son chemin GitHub — et le noter dans le README,
   parce que ça change la boucle de développement du plugin.
2. **Résolution de `source` dans `marketplace.json`** (Task 2). `"../plugin"` est
   relatif au répertoire `.claude-plugin/`. Si la résolution s'avère relative à
   la racine du dépôt, la valeur devient `"./plugin"` — le test
   « la marketplace déclare le plugin, à une source qui existe » est écrit pour
   attraper le cas, mais son calcul de chemin est à ajuster en même temps.
3. **Variabilité du rejeu des fixtures** (Tasks 3 à 6). Un écart sur autre chose
   que le champ `name` se corrige dans le fichier de mode, jamais dans la
   fixture. Si un même écart revient à deux rejeux, c'est une règle manquante,
   pas un aléa.
4. **`claude plugin install` en non-interactif** (Task 7, Step 5). Jamais
   éprouvé jusqu'ici : les tests du plan précédent utilisaient un `claude`
   bouchonné.

## Suite

Reste du spec, après ce plan : la migration de Compte-de-Famille (§17), à mener
avec le mode « migrer » une fois `v1.1.0` publiée. La fixture de la Task 4 en est
la répétition ; la migration réelle en sera la première exécution en vraie
grandeur, et le premier endroit où l'on saura si les modes tiennent hors
laboratoire.