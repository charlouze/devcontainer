'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const { verifier } = require('../lib/devcontainer-invariants.cjs');

const FIXTURES = path.join(__dirname, '../fixtures/onboarding');
const TEMPLATE = path.join(
  __dirname,
  '../../plugin/skills/onboard-devcontainer/references/devcontainer.template.json'
);

// Chaque ligne de commentaire du template, prise individuellement — pas
// recopiée à la main ici, pour que l'oracle suive le template au lieu de s'en
// écarter en silence s'il change. Les lignes "//" isolées, qui ne font que
// séparer deux paragraphes d'un même bloc, n'apportent rien à vérifier.
const lignesCommentaires = (texte) =>
  texte
    .split('\n')
    .map((ligne) => ligne.trim())
    .filter((ligne) => ligne.startsWith('//') && ligne !== '//');

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

// Les commentaires du template sont un livrable : une sortie attendue qui en
// aurait perdu un seul, où qu'il soit dans le fichier, entérinerait sa perte.
// Une assertion par ligne de commentaire, pas juste par bloc : un report
// partiel à l'intérieur d'un bloc (une des trois paragraphes de `runArgs`,
// par exemple) doit être aussi détectable qu'un bloc entier manquant.
test('chaque sortie attendue conserve les commentaires du template', () => {
  const commentaires = lignesCommentaires(fs.readFileSync(TEMPLATE, 'utf8'));
  assert.ok(commentaires.length > 0, 'le template ne porte aucun commentaire à vérifier');

  const cas = fs.readdirSync(FIXTURES, { withFileTypes: true }).filter((e) => e.isDirectory());
  for (const entree of cas) {
    const fichier = path.join(FIXTURES, entree.name, 'attendu/devcontainer.json');
    if (!fs.existsSync(fichier)) continue;
    const texte = fs.readFileSync(fichier, 'utf8');
    for (const ligne of commentaires) {
      assert.ok(texte.includes(ligne), `commentaire perdu (${entree.name}) : ${ligne}`);
    }
  }
});
