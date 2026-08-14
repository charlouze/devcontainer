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
  // `source` est relatif à la racine de la marketplace — le dossier qui
  // *contient* `.claude-plugin/` — et non à `.claude-plugin/` lui-même où vit
  // marketplace.json. `claude plugin validate` le confirme explicitement : un
  // chemin remontant (`../plugin`) y est rejeté avec un message qui dit texto
  // de le remplacer par `./plugin`. Une résolution relative au fichier aurait
  // semblé la plus naturelle à écrire ; c'est l'autre qu'implémente le CLI.
  const chemin = path.join(racine, entrees[0].source);
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
