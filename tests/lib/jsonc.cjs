'use strict';

/**
 * Les devcontainer.json sont du JSONC : commentaires de ligne, commentaires de
 * bloc, virgules traînantes. JSON.parse refuse les trois. Les commentaires du
 * template sont un livrable à part entière — les lire, et donc les préserver,
 * n'est pas optionnel.
 *
 * Le découpage suit l'état « dans une chaîne » plutôt qu'une expression
 * régulière : un `//` dans une URL n'est pas un commentaire.
 */

/**
 * Avance d'un caractère dans `texte` à partir de l'index `i` en tenant à jour
 * l'état « dans une chaîne » (guillemet ouvrant/fermant, backslash
 * d'échappement qui avale le caractère suivant sans le réinterpréter).
 *
 * Cette mécanique est identique pour `stripComments` et `stripTrailingCommas` :
 * toutes deux doivent ignorer `//`, `/*` et `,` tant qu'on est à l'intérieur
 * d'une chaîne JSON. La dupliquer serait le genre d'endroit où un futur cas
 * d'échappement ne serait corrigé que d'un côté. Rend `{ dansChaine, suivant }`
 * où `suivant` est l'index du prochain caractère à traiter — 2 de plus en cas
 * d'échappement, sinon 1 de plus.
 */
function avancerDansChaine(texte, i, dansChaine) {
  const c = texte[i];

  if (dansChaine) {
    if (c === '\\') return { dansChaine: true, suivant: i + 2, echappe: texte[i + 1] ?? '' };
    return { dansChaine: c !== '"', suivant: i + 1, echappe: null };
  }

  if (c === '"') return { dansChaine: true, suivant: i + 1, echappe: null };

  return { dansChaine: false, suivant: i + 1, echappe: null };
}

function stripComments(texte) {
  let sortie = '';
  let i = 0;
  let dansChaine = false;

  while (i < texte.length) {
    const c = texte[i];

    if (dansChaine || c === '"') {
      const etat = avancerDansChaine(texte, i, dansChaine);
      sortie += etat.echappe === null ? c : c + etat.echappe;
      dansChaine = etat.dansChaine;
      i = etat.suivant;
      continue;
    }

    if (c === '/' && texte[i + 1] === '/') {
      while (i < texte.length && texte[i] !== '\n') i += 1;
      continue;
    }

    if (c === '/' && texte[i + 1] === '*') {
      i += 2;
      while (i < texte.length && !(texte[i] === '*' && texte[i + 1] === '/')) i += 1;
      i += 2;
      continue;
    }

    sortie += c;
    i += 1;
  }

  return sortie;
}

function stripTrailingCommas(texte) {
  let sortie = '';
  let dansChaine = false;
  let i = 0;

  while (i < texte.length) {
    const c = texte[i];

    if (dansChaine || c === '"') {
      const etat = avancerDansChaine(texte, i, dansChaine);
      sortie += etat.echappe === null ? c : c + etat.echappe;
      dansChaine = etat.dansChaine;
      i = etat.suivant;
      continue;
    }

    if (c === ',') {
      let j = i + 1;
      while (j < texte.length && /\s/.test(texte[j])) j += 1;
      if (texte[j] === '}' || texte[j] === ']') {
        i += 1;
        continue;
      }
    }

    sortie += c;
    i += 1;
  }

  return sortie;
}

function parseJsonc(texte) {
  return JSON.parse(stripTrailingCommas(stripComments(texte)));
}

module.exports = { parseJsonc, stripComments, stripTrailingCommas };
