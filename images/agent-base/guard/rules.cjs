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
  // Les deux règles de push partagent deux motifs.
  //
  // Le préfixe (?:-\S+(?:\s+[^\s-]\S*)?\s+)* absorbe les options globales de
  // git, qui se glissent entre `git` et `push`. Sans lui, `git -C /w push
  // origin main` — une invocation parfaitement ordinaire, sans guillemets ni
  // détour — passe sous les deux règles, tout comme `git -c user.name=x push`
  // ou `git --no-pager push`. Le groupe optionnel intérieur consomme la VALEUR
  // de l'option quand elle est séparée (`-C /w`, `-c k=v`) ; il exclut les
  // valeurs commençant par « - » pour ne pas avaler l'option suivante, et le
  // moteur revient en arrière de lui-même quand la « valeur » qu'il avait prise
  // était en fait `push`.
  //
  // La borne [^\n;&|]* entre `push` et ce qui suit tient l'autre bout : sans
  // elle, une commande enchaînée par && ou ; pourrait faire correspondre un mot
  // de la commande suivante, qui n'a rien à voir avec ce push-là
  // (`git push origin ma-branche && echo main` doit passer).
  [
    // Référence entière, pas une sous-chaîne : elle doit être précédée d'un
    // espace, de « : », d'un guillemet, de « + » (refspec forcé) ou de
    // refs/heads/, et suivie d'un espace, d'un guillemet, de la fin de la
    // commande ou d'un métacaractère shell (; & | )). Sans ce dernier volet,
    // un point-virgule, un && ou une parenthèse fermante en toute fin de
    // ligne désarme la règle alors que `git push origin main; echo fait` est
    // un one-liner ordinaire, pas une construction adverse.
    /\bgit\s+(?:-\S+(?:\s+[^\s-]\S*)?\s+)*push\b[^\n;&|]*(?<=[\s:+'"]|refs\/heads\/)(main|master)(?=[\s;&|)'"]|$)/,
    'Pousser sur main est bloqué : ouvre une branche et une pull request. ' +
      "L'intégration est un geste humain, dans l'interface GitHub.",
  ],
  [
    // Deux familles ici. Les options qui publient tout (--all, --mirror…), et
    // le refspec à source vide `:branche`, qui SUPPRIME la référence distante.
    // Ce second cas n'est pas décoratif : une branche poussée est la seule copie
    // du travail qui survive à la recréation du container (cf. README), donc
    // l'effacer à distance est exactement la perte de données que ce dispositif
    // existe pour fermer. Le \s\+?:\S vise le deux-points en TÊTE de refspec,
    // « + » de forçage compris ; `HEAD:ma-branche` et `ma-branche:autre` gardent
    // une source à gauche et restent des pushes ordinaires.
    //
    // --delete doit précéder -d dans l'alternation : elle rend la première
    // branche qui matche, et l'ordre inverse ferait consommer -d au début de
    // --delete, laissant un \b qui échoue juste après.
    /\bgit\s+(?:-\S+(?:\s+[^\s-]\S*)?\s+)*push\b[^\n;&|]*(\s(--all|--mirror|--tags|--prune|--delete|-d)\b|\s\+?:\S)/,
    'Cette forme de git push publie plus que la branche courante — toutes les ' +
      'branches, tous les tags — ou supprime une référence distante. Pousse ' +
      'une branche nommée.',
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
  // Le préfixe (?:-\S+\s+)* absorbe les options globales, qui se glissent entre
  // la commande et le verbe. `terraform -chdir=infra apply` est la forme
  // ordinaire dès que le Terraform vit dans un sous-répertoire ; sans ce
  // groupe, elle passerait sous les deux règles. Même construction que le
  // préfixe des règles `git push`.
  //
  // `plan`, `init`, `fmt`, `validate` et `show` restent libres : sans
  // Application Default Credentials, `plan` échoue de lui-même. Une règle qui
  // le bloquerait prétendrait protéger ce que l'absence de credential protège
  // déjà.
  [
    /(^|[\s;&|(])(terraform|tofu)\s+(?:-\S+\s+)*(apply|destroy|import|force-unlock|taint|untaint)\b/,
    'Les commandes Terraform qui écrivent sont bloquées. `init`, `fmt`, ' +
      '`validate`, `plan` et `show` restent disponibles.',
  ],
  // Les sous-commandes d'état ont un mot de plus, d'où une seconde entrée
  // plutôt qu'une alternance qui rendrait le premier motif illisible.
  [
    /(^|[\s;&|(])(terraform|tofu)\s+(?:-\S+\s+)*state\s+(rm|mv|push|replace-provider)\b/,
    "Réécrire l'état Terraform est bloqué : c'est le moyen détourné de " +
      "changer l'infrastructure sans passer par un `apply`.",
  ],
  [
    /\b(npm|pnpm|yarn)\s+publish\b/,
    'Publier un package est hors du périmètre de ces projets.',
  ],
  [
    // Liste blanche par lookahead négatif, pas liste noire : tout ce qui n'est
    // pas explicitement nommé est refusé, y compris `gh api` et les
    // sous-commandes que gh ajoutera demain. Le \s* à l'intérieur du
    // lookahead absorbe l'espace qui reste quel que soit ce que \s+ a déjà
    // consommé avant lui : sans lui, un espace double ou une tabulation après
    // gh fait reculer \s+ d'un cran par backtracking, le lookahead se
    // retrouve à tester une chaîne qui commence par un espace, aucune
    // alternative ne matche alors, la négation réussit à tort et une
    // commande pourtant permise se retrouve bloquée.
    // `gh run list|view|watch` et `gh pr checks` sont en lecture seule et ne
    // donnent aucun droit d'écriture : suivre la CI d'une PR qu'on vient
    // d'ouvrir fait partie du geste, et sans eux l'agent ouvre une PR qu'il ne
    // peut plus regarder échouer.
    /\bgh\s+(?!\s*(pr\s+(create|edit|view|list|diff|status|checkout|comment|ready|checks)|run\s+(list|view|watch)|issue\s+(view|list|create|edit|comment)|repo\s+view|auth\s+status|browse|search|--version|--help)\b)/,
    'Seules la création, la modification et la lecture de pull requests sont ' +
      'ouvertes à gh. Le merge, la fermeture, `gh api` et le reste sont refusés ' +
      "par défaut — l'intégration est un geste humain.",
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
