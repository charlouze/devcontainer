'use strict';

const test = require('node:test');
const assert = require('node:assert');

const { parseJsonc } = require('../lib/jsonc.cjs');

test('un commentaire de ligne est retiré', () => {
  assert.deepStrictEqual(parseJsonc('{\n  // note\n  "a": 1\n}'), { a: 1 });
});

test('un commentaire de bloc est retiré', () => {
  assert.deepStrictEqual(parseJsonc('{ /* note\n   suite */ "a": 1 }'), { a: 1 });
});

test('une chaîne contenant // survit', () => {
  assert.deepStrictEqual(parseJsonc('{ "a": "https://exemple.test/x" }'), {
    a: 'https://exemple.test/x',
  });
});

test('une chaîne contenant un guillemet échappé ne désynchronise pas la lecture', () => {
  assert.deepStrictEqual(parseJsonc('{ "a": "dit \\"bonjour\\"", "b": 1 }'), {
    a: 'dit "bonjour"',
    b: 1,
  });
});

test('une virgule traînante est tolérée', () => {
  assert.deepStrictEqual(parseJsonc('{ "a": [1, 2,], }'), { a: [1, 2] });
});

test('un JSON réellement invalide lève', () => {
  assert.throws(() => parseJsonc('{ "a": }'));
});
