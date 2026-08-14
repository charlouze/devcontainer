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
