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
