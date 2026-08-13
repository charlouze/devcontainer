'use strict';

/**
 * Moteur de règles du garde-fou.
 *
 * Module volontairement pur : pas d'accès disque, pas de `process.exit`, pas de
 * lecture d'environnement. Tout ce qui touche au système vit dans
 * agent-guard.cjs. C'est ce qui rend ces règles testables sans construire
 * d'image.
 */

const MAX_RULES_BYTES = 65536;
const MAX_RULES_COUNT = 100;

/** Interdits sur les commandes Bash. */
const BASH_RULES = [
  [
    /\bgit\s+push\b/,
    'git push est bloqué dans le sandbox. Commits et branches locales : libre. ' +
      'Le push est une action humaine — fais relire le diff.',
  ],
  [
    /\bgit\s+(remote\s+(set-url|add|rename)|config\s+(--global|--system))\b/,
    "Modifier les remotes ou la config git globale est bloqué : c'est un moyen " +
      'détourné de rediriger un push.',
  ],
  [
    /\bfirebase\s+(deploy|hosting:|functions:|firestore:delete|target|login|apps:|projects:)/,
    'Les commandes Firebase qui touchent au projet distant sont bloquées. ' +
      'Seuls les émulateurs locaux sont autorisés (mise run emulators).',
  ],
  [
    /(^|[\s;&|(])(gcloud|gsutil|bq)([\s;&|)]|$)/,
    'Aucun accès à Google Cloud depuis ce container, par construction.',
  ],
  [
    /\b(npm|pnpm|yarn)\s+publish\b/,
    'Publier un package est hors du périmètre de ces projets.',
  ],
  [
    /\bgh\s+(secret|release|workflow|auth\s+token|repo\s+(delete|edit))/,
    'Les commandes gh qui écrivent sur GitHub sont bloquées.',
  ],
  [
    /\bcurl\b[^|;&]*\|\s*(sudo\s+)?(ba|z|d)?sh\b/,
    'Exécuter un script téléchargé à la volée est bloqué. Télécharge-le, lis-le, ' +
      'puis exécute-le.',
  ],
  // Pas de règle sur le jeton d'authentification de l'agent : elle serait
  // décorative. Voir « Ce que le garde-fou ne protège pas » dans le README.
];

/** Chemins interdits en lecture comme en écriture, quel que soit l'outil. */
const PATH_RULES = [
  [
    /(^|[\\/])\.env($|[.\\/])/i,
    'Les fichiers .env sont hors limites : ils portent la configuration ' +
      "d'émulateurs et potentiellement des identifiants de test.",
  ],
  [
    /\.credentials\.json$|[\\/]\.ssh[\\/]|id_(rsa|ecdsa|ed25519)\b|\.pem$/i,
    'Les secrets et clés privées sont hors limites.',
  ],
  [
    /serviceaccount.*\.json$|.*-firebase-adminsdk-.*\.json$/i,
    'Les clés de compte de service Google sont hors limites — et ne devraient ' +
      'de toute façon jamais entrer dans ce container.',
  ],
  [
    /[\\/]\.history[\\/]bash_history$/,
    "L'historique de shell est hors limites : il contient régulièrement des " +
      'jetons collés à la main.',
  ],
];

function firstMatch(rules, value) {
  if (typeof value !== 'string') return null;
  for (const [pattern, reason] of rules) {
    if (pattern.test(value)) return reason;
  }
  return null;
}

function applyRuleSet(ruleSet, command, target) {
  return firstMatch(ruleSet.bash, command) || firstMatch(ruleSet.paths, target);
}

/**
 * Rend la raison du blocage, ou null si l'appel est autorisé.
 *
 * L'ordre est la garantie de sécurité : le socle est évalué **avant** les
 * règles projet. Le fichier de règles projet vit dans le workspace et est donc
 * éditable par l'agent — mais comme un blocage du socle sort avant qu'on l'ait
 * regardé, ni le supprimer ni y écrire une regex à backtracking catastrophique
 * (qui ferait expirer le hook) ne peut lever un interdit du socle.
 */
function evaluate(payload, projectRules) {
  const input = (payload && payload.tool_input) || {};
  const command = payload && payload.tool_name === 'Bash' ? input.command : undefined;
  const target = input.file_path || input.path || input.notebook_path;

  const base = applyRuleSet({ bash: BASH_RULES, paths: PATH_RULES }, command, target);
  if (base) return base;

  if (projectRules) {
    const extra = applyRuleSet(projectRules, command, target);
    if (extra) return extra;
  }

  return null;
}

function compileList(raw, warnings, kind) {
  if (raw === undefined) return [];
  if (!Array.isArray(raw)) {
    warnings.push(`la clé « ${kind} » des règles projet n'est pas une liste, ignorée.`);
    return [];
  }

  let list = raw;
  if (list.length > MAX_RULES_COUNT) {
    warnings.push(
      `les règles projet « ${kind} » dépassent ${MAX_RULES_COUNT} entrées, ` +
        'les suivantes sont ignorées.'
    );
    list = list.slice(0, MAX_RULES_COUNT);
  }

  const compiled = [];
  for (const rule of list) {
    if (!rule || typeof rule.pattern !== 'string' || typeof rule.reason !== 'string') {
      warnings.push(`une règle projet « ${kind} » sans pattern ou sans reason est ignorée.`);
      continue;
    }
    // Les drapeaux g et y rendent le test dépendant de lastIndex : deux appels
    // identiques donneraient des verdicts différents. On les retire.
    const flags = String(rule.flags || '').replace(/[gy]/g, '');
    try {
      compiled.push([new RegExp(rule.pattern, flags), rule.reason]);
    } catch {
      warnings.push(`règle projet « ${kind} » à regex invalide, ignorée : ${rule.pattern}`);
    }
  }
  return compiled;
}

/**
 * Compile le contenu d'un guard-rules.json.
 *
 * Ne jette jamais : une erreur de configuration produit un avertissement et un
 * retour à vide, jamais un blocage total ni un fail-open silencieux.
 */
function compileProjectRules(text) {
  const warnings = [];

  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    warnings.push('guard-rules.json illisible (JSON invalide), règles projet ignorées.');
    return { rules: null, warnings };
  }

  if (!parsed || typeof parsed !== 'object') {
    warnings.push("guard-rules.json n'est pas un objet, règles projet ignorées.");
    return { rules: null, warnings };
  }

  return {
    rules: {
      bash: compileList(parsed.bash, warnings, 'bash'),
      paths: compileList(parsed.paths, warnings, 'paths'),
    },
    warnings,
  };
}

module.exports = {
  evaluate,
  compileProjectRules,
  MAX_RULES_BYTES,
  MAX_RULES_COUNT,
};
