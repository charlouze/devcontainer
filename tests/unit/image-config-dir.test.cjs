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
