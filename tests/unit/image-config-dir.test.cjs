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

// Le nom de l'utilisateur est un ARG : les chemins du Dockerfile s'écrivent
// `/home/${USERNAME}/…` là où les invariants les portent développés. On
// substitue avant de comparer, plutôt que de figer « dev » des deux côtés.
function repertoiresCrees() {
  const utilisateur = dockerfile.match(/^ARG USERNAME=(\S+)$/m)[1];
  // Les continuations de ligne sont repliées d'abord : le mkdir des points de
  // montage tient sur huit lignes, et c'est l'instruction entière qu'on veut.
  const instruction = dockerfile
    .replaceAll('${USERNAME}', utilisateur)
    .replace(/\\\r?\n\s*/g, ' ')
    .split(/\r?\n/)
    .find((ligne) => /^RUN mkdir -p \/home\//.test(ligne));
  assert.ok(instruction, 'aucun `RUN mkdir -p /home/…` dans le Dockerfile');
  return { utilisateur, chemins: new Set(instruction.split(/\s+/)) };
}

// Rien d'autre ne tient ces deux listes ensemble. Un point de montage absent de
// l'image est créé par Docker en root:root, et `dev` ne peut alors rien y
// écrire : gh écrirait ailleurs — ou pas du tout — et la connexion mourrait à
// chaque recréation SANS QUE RIEN NE LE SIGNALE. Une dérive d'un caractère dans
// le mkdir suffit, d'où ce test plutôt qu'une relecture attentive.
test('chaque montage partagé sous /home préexiste dans le Dockerfile', () => {
  const { utilisateur, chemins } = repertoiresCrees();
  const cibles = Object.keys(MONTAGES_PARTAGES).filter((cible) =>
    cible.startsWith(`/home/${utilisateur}/`)
  );
  assert.ok(cibles.length > 0, 'aucun montage partagé sous /home : la liste a changé de forme');

  for (const cible of cibles) {
    assert.ok(
      chemins.has(cible),
      `${cible} (montage ${MONTAGES_PARTAGES[cible]}) n'est pas créé par le mkdir du Dockerfile`
    );
  }
});

// Le cache Playwright n'est pas content-addressed mais compté par références :
// chaque `playwright install` écrit dans `<cache>/.links/` le chemin absolu du
// paquet playwright-core qui installe, puis supprime tout répertoire de
// navigateur qu'aucun lien encore résolvable ne réclame. D'un container à
// l'autre, le chemin du projet voisin n'existe pas : son lien est déclaré cassé
// et ses navigateurs partent avec. Sur un volume partagé, chaque provisionnement
// vide donc le cache de tous les autres projets. La variable coupe ce ramassage.
test("l'image de base désactive le ramassage de navigateurs de Playwright", () => {
  const occurrences = dockerfile.match(/^ENV PLAYWRIGHT_SKIP_BROWSER_GC=(\S+)$/gm) ?? [];
  assert.strictEqual(
    occurrences.length,
    1,
    `${occurrences.length} définitions de PLAYWRIGHT_SKIP_BROWSER_GC dans le Dockerfile`
  );
  assert.strictEqual(occurrences[0], 'ENV PLAYWRIGHT_SKIP_BROWSER_GC=1');
});

// La variable ne se justifie que par le partage du cache entre projets. Un
// volume par projet rendrait au contraire le ramassage souhaitable : il purgerait
// les versions abandonnées du projet lui-même, sans jamais toucher à celles d'un
// autre. Si le montage cessait d'être partagé, ce test tomberait et rappellerait
// de retirer la variable plutôt que de la laisser gonfler le volume pour rien.
test('le cache Playwright est un montage partagé entre projets', () => {
  assert.strictEqual(
    MONTAGES_PARTAGES['/home/dev/.cache/ms-playwright'],
    'agent-playwright',
    "le cache Playwright n'est plus partagé : PLAYWRIGHT_SKIP_BROWSER_GC n'a plus lieu d'être"
  );
});

// gh résout sa configuration dans `$XDG_CONFIG_HOME/gh`. L'image fige la
// variable à sa valeur par défaut pour qu'aucune couche ne puisse la déplacer en
// silence — auquel cas le volume agent-gh deviendrait inerte exactement comme un
// CLAUDE_CONFIG_DIR oublié. Le test tient la variable et le montage en accord.
test('XDG_CONFIG_HOME est le parent du montage gh', () => {
  const occurrences = dockerfile.match(/^ENV XDG_CONFIG_HOME=(\S+)$/gm) ?? [];
  assert.strictEqual(occurrences.length, 1, `${occurrences.length} définitions de XDG_CONFIG_HOME`);
  const valeur = occurrences[0].replace(/^ENV XDG_CONFIG_HOME=/, '');

  const cible = Object.keys(MONTAGES_PARTAGES).find((c) => MONTAGES_PARTAGES[c] === 'agent-gh');
  assert.strictEqual(`${valeur}/gh`, cible, `${valeur}/gh n'est pas la cible du montage agent-gh`);
});
