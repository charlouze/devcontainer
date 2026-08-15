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
        'source=agent-gh,target=/home/dev/.config/gh,type=volume',
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

test('un JSON valide mais non-objet (null, nombre, chaîne) produit une violation unique, sans jeter', () => {
  for (const texte of ['null', '42', '"texte"']) {
    assert.deepStrictEqual(verifier(texte).map((v) => v.id), ['json']);
  }
});

test('chaque invariant porte un id unique et un libellé', () => {
  const ids = INVARIANTS.map((i) => i.id);
  assert.strictEqual(new Set(ids).size, ids.length);
  for (const invariant of INVARIANTS) {
    assert.ok(invariant.libelle.length > 10, `libellé trop court : ${invariant.id}`);
  }
});
