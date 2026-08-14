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
// avec le container. Avec elle, il atterrit dans
// `/home/dev/.claude/.claude.json`, donc dans le volume.
test("l'image de base exporte CLAUDE_CONFIG_DIR", () => {
  assert.match(dockerfile, /^ENV CLAUDE_CONFIG_DIR=\S+$/m);
});

// Recherche globale et non la première occurrence : Docker retient la
// DERNIÈRE définition d'une variable ENV répétée. Prendre la première
// laisserait passer une seconde ligne divergente sans que le test le voie,
// alors que l'image construite suivrait, elle, la seconde.
test('CLAUDE_CONFIG_DIR est défini une seule fois', () => {
  const occurrences = dockerfile.match(/^ENV CLAUDE_CONFIG_DIR=(\S+)$/gm) ?? [];
  assert.strictEqual(
    occurrences.length,
    1,
    `${occurrences.length} définitions de CLAUDE_CONFIG_DIR dans le Dockerfile, Docker retiendrait la dernière`
  );
});

// Le cœur du test : la valeur et la cible du montage `agent-claude` doivent
// rester la même chaîne. Si elles divergent, l'état se scinde entre deux racines
// dont une seule est persistée, et rien ne le signale à l'exécution.
//
// On prend la DERNIÈRE occurrence, jamais la première : c'est celle que Docker
// honore. Ce test peut s'exécuter indépendamment du précédent (l'ordre entre
// tests n'est pas garanti), donc il ne peut pas compter sur l'unicité déjà
// vérifiée ailleurs pour rester correct par lui-même.
test('la valeur est la cible du montage de login partagé', () => {
  const occurrences = dockerfile.match(/^ENV CLAUDE_CONFIG_DIR=(\S+)$/gm);
  const derniere = occurrences[occurrences.length - 1];
  const valeur = derniere.replace(/^ENV CLAUDE_CONFIG_DIR=/, '');
  assert.strictEqual(
    MONTAGES_PARTAGES[valeur],
    'agent-claude',
    `${valeur} n'est pas la cible du montage agent-claude`
  );
});
