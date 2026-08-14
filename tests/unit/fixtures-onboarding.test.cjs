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
