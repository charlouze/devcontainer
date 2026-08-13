#!/usr/bin/env node
'use strict';

/**
 * Garde-fou PreToolUse pour les sessions d'agent autonome (mode YOLO).
 *
 * `--dangerously-skip-permissions` saute les demandes de confirmation, pas les
 * hooks : un PreToolUse qui sort en code 2 bloque quand même l'appel d'outil.
 * C'est donc ici que vivent les interdits qui doivent tenir quand l'agent a
 * carte blanche.
 *
 * Déployé root-only en /usr/local/lib/claude-guard/ et déclaré depuis
 * /etc/claude-code/managed-settings.json, de priorité maximale et non
 * surchargeable par les settings user ou projet. Combiné à `no-new-privileges`
 * — l'utilisateur `dev` ne peut jamais devenir root — ni le script ni sa
 * déclaration ne sont modifiables depuis la session. C'est ce qui le distingue
 * d'un hook posé dans le workspace, que l'agent pourrait éditer.
 *
 * Conventions de sortie : 0 = laisser passer, 2 = bloquer, le message sur
 * stderr étant renvoyé à l'agent.
 */

const fs = require('fs');
const path = require('path');
const { evaluate, compileProjectRules, MAX_RULES_BYTES } = require('./rules.cjs');

// Activation par marqueur root-only, et non par variable d'environnement :
// l'agent contrôle l'environnement des processus qu'il lance, donc un test sur
// une variable se contourne par `env -u`. Ce chemin est en dur et ne doit
// jamais devenir configurable.
const MARKER = '/etc/claude-guard/enabled';
if (!fs.existsSync(MARKER)) process.exit(0);

/**
 * Charge les règles additionnelles du projet, s'il y en a.
 *
 * Le fichier vit dans le workspace et est donc éditable par l'agent. Ce n'est
 * pas un problème : elles ne peuvent qu'ajouter au socle, et le socle est
 * évalué avant. CLAUDE_PROJECT_DIR est lui aussi sous contrôle de l'agent —
 * au pire il pointe ailleurs, ce qui retire des interdits ajoutés, jamais du
 * socle.
 */
function loadProjectRules() {
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const file = path.join(projectDir, '.devcontainer', 'guard-rules.json');

  let stat;
  try {
    stat = fs.statSync(file);
  } catch {
    return { rules: null, warnings: [] }; // absent : cas normal
  }

  if (stat.size > MAX_RULES_BYTES) {
    return {
      rules: null,
      warnings: [`guard-rules.json dépasse ${MAX_RULES_BYTES} octets, ignoré.`],
    };
  }

  try {
    return compileProjectRules(fs.readFileSync(file, 'utf8'));
  } catch {
    return { rules: null, warnings: ['guard-rules.json illisible, ignoré.'] };
  }
}

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => (raw += chunk));
process.stdin.on('end', () => {
  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    // Entrée illisible : on ne bloque pas sur une erreur d'infrastructure.
    process.exit(0);
  }

  const { rules, warnings } = loadProjectRules();
  for (const warning of warnings) {
    process.stderr.write(`Garde-fou : ${warning}\n`);
  }

  const reason = evaluate(payload, rules);
  if (reason) {
    process.stderr.write(`Bloqué par le garde-fou du sandbox : ${reason}\n`);
    process.exit(2);
  }

  process.exit(0);
});
