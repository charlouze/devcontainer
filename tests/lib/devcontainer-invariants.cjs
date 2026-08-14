'use strict';

/**
 * Ce qu'un devcontainer.json produit par la skill d'onboarding doit satisfaire,
 * quel que soit le mode qui l'a produit.
 *
 * Ces règles sont mécaniques, donc tenues par du code. La liste de contrôle
 * finale de plugin/skills/onboard-devcontainer/SKILL.md en est le reflet en
 * prose, et un test (tests/unit/skill-checklist.test.cjs) vérifie que les deux
 * restent en accord : toute modification ici est à répercuter là-bas.
 */

const { parseJsonc } = require('./jsonc.cjs');

const IMAGE = /^ghcr\.io\/charlouze\/devcontainer-(agent-base|web):\d+$/;
const POST_CREATE = '/usr/local/share/devcontainer/post-create.sh';
const CAPS_AUTORISEES = ['CHOWN', 'FOWNER', 'DAC_OVERRIDE', 'SETUID', 'SETGID'];
const OPTIONS_AUTORISEES = ['--security-opt', '--cap-drop', '--cap-add'];

// Cibles dont la source est imposée : le login et les caches content-addressed
// sont mutualisés entre projets, le partage y étant sûr par construction.
const MONTAGES_PARTAGES = {
  '/home/dev/.claude': 'agent-claude',
  '/home/dev/.cache/pnpm-store': 'agent-pnpm-store',
  '/home/dev/.cache/ms-playwright': 'agent-playwright',
};

// Cibles dont la source doit être propre au projet : deux containers ouverts en
// même temps ne doivent se disputer ni le backend JetBrains ni l'historique.
const MONTAGES_PROJET = ['/home/dev/.cache', '/home/dev/.history'];

const INVARIANTS = [
  { id: 'image-tag', libelle: "l'image est une image du dépôt, sur un tag de majeure (`:1`)" },
  { id: 'utilisateurs', libelle: 'containerUser vaut root et remoteUser vaut dev' },
  { id: 'post-create', libelle: `postCreateCommand vaut exactement ${POST_CREATE}` },
  {
    id: 'runargs-securite',
    libelle: 'runArgs porte no-new-privileges, --cap-drop ALL, et aucune capability hors liste',
  },
  {
    id: 'runargs-parser',
    libelle: 'runArgs ne contient que --security-opt, --cap-drop et --cap-add',
  },
  { id: 'volumes', libelle: 'les cinq montages attendus, partagés ou préfixés par le projet' },
  { id: 'pas-de-socket-docker', libelle: "aucun montage de type bind depuis l'hôte" },
  {
    id: 'pas-de-variable-garde-fou',
    libelle: "aucune variable d'environnement ne prétend piloter le garde-fou",
  },
  { id: 'ports-libelles', libelle: 'chaque port de forwardPorts porte un libellé' },
];

function paires(liste) {
  const sortie = [];
  for (let i = 0; i < liste.length; i += 2) sortie.push([liste[i], liste[i + 1]]);
  return sortie;
}

function champsDuMontage(montage) {
  const champs = {};
  for (const morceau of String(montage).split(',')) {
    const index = morceau.indexOf('=');
    if (index > 0) champs[morceau.slice(0, index)] = morceau.slice(index + 1);
  }
  return champs;
}

function verifier(texte) {
  const violations = [];
  const refuse = (id, message) => violations.push({ id, message });

  let config;
  try {
    config = parseJsonc(texte);
  } catch (erreur) {
    return [{ id: 'json', message: `fichier illisible : ${erreur.message}` }];
  }

  if (!IMAGE.test(String(config.image || ''))) {
    refuse('image-tag', `image inattendue : ${config.image}. Attendu un tag de majeure.`);
  }

  if (config.containerUser !== 'root' || config.remoteUser !== 'dev') {
    refuse(
      'utilisateurs',
      `containerUser/remoteUser valent ${config.containerUser}/${config.remoteUser}, attendu root/dev.`
    );
  }

  if (config.postCreateCommand !== POST_CREATE) {
    refuse('post-create', `postCreateCommand vaut ${config.postCreateCommand}.`);
  }

  const runArgs = Array.isArray(config.runArgs) ? config.runArgs : [];
  const options = paires(runArgs);
  const contient = (option, valeur) =>
    options.some(([o, v]) => o === option && v === valeur);

  if (!contient('--security-opt', 'no-new-privileges') || !contient('--cap-drop', 'ALL')) {
    refuse('runargs-securite', 'no-new-privileges et --cap-drop ALL sont obligatoires.');
  }
  for (const [option, valeur] of options) {
    if (option === '--cap-add' && !CAPS_AUTORISEES.includes(valeur)) {
      refuse('runargs-securite', `capability hors liste : ${valeur}.`);
    }
    if (!OPTIONS_AUTORISEES.includes(option)) {
      refuse('runargs-parser', `option ${option} : le parser d'IntelliJ échouera dessus.`);
    }
  }

  const montages = new Map();
  for (const montage of config.mounts || []) {
    const champs = champsDuMontage(montage);
    montages.set(champs.target, champs);
    if (champs.type === 'bind') {
      refuse('pas-de-socket-docker', `montage bind depuis l'hôte : ${montage}.`);
    }
  }
  for (const [cible, source] of Object.entries(MONTAGES_PARTAGES)) {
    if (!montages.has(cible)) refuse('volumes', `montage manquant : ${cible}.`);
    else if (montages.get(cible).source !== source) {
      refuse('volumes', `${cible} doit venir du volume partagé ${source}.`);
    }
  }
  for (const cible of MONTAGES_PROJET) {
    if (!montages.has(cible)) refuse('volumes', `montage manquant : ${cible}.`);
    else if (/^agent-/.test(montages.get(cible).source || '')) {
      refuse('volumes', `${cible} doit être propre au projet, pas un volume agent-*.`);
    }
  }

  for (const cle of Object.keys(config.containerEnv || {})) {
    if (/GUARD|SANDBOX/i.test(cle)) {
      refuse(
        'pas-de-variable-garde-fou',
        `${cle} : le garde-fou s'active par marqueur root-only, jamais par variable.`
      );
    }
  }

  const libelles = config.portsAttributes || {};
  for (const port of config.forwardPorts || []) {
    if (!libelles[String(port)] || !libelles[String(port)].label) {
      refuse('ports-libelles', `le port ${port} est ouvert sans libellé.`);
    }
  }

  return violations;
}

module.exports = { verifier, INVARIANTS, IMAGE, POST_CREATE };
