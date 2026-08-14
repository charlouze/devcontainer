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

function stripComments(texte) {
  let sortie = '';
  let i = 0;
  let dansChaine = false;

  while (i < texte.length) {
    const c = texte[i];

    if (dansChaine) {
      sortie += c;
      if (c === '\\') {
        sortie += texte[i + 1] ?? '';
        i += 2;
        continue;
      }
      if (c === '"') dansChaine = false;
      i += 1;
      continue;
    }

    if (c === '"') {
      dansChaine = true;
      sortie += c;
      i += 1;
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

  for (let i = 0; i < texte.length; i += 1) {
    const c = texte[i];

    if (dansChaine) {
      sortie += c;
      if (c === '\\') {
        sortie += texte[i + 1] ?? '';
        i += 1;
        continue;
      }
      if (c === '"') dansChaine = false;
      continue;
    }

    if (c === '"') {
      dansChaine = true;
      sortie += c;
      continue;
    }

    if (c === ',') {
      let j = i + 1;
      while (j < texte.length && /\s/.test(texte[j])) j += 1;
      if (texte[j] === '}' || texte[j] === ']') continue;
    }

    sortie += c;
  }

  return sortie;
}

function parseJsonc(texte) {
  return JSON.parse(stripTrailingCommas(stripComments(texte)));
}

module.exports = { parseJsonc, stripComments, stripTrailingCommas };
