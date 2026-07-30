// Paridade entre os dois sanitizadores de tópico FCM.
//
// A mesma lógica existe em lib/utils/fcm_topics.dart (usada pelo app para
// ASSINAR o tópico) e em functions/index.js (usada pela Cloud Function para
// PUBLICAR nele). Se divergirem em um único caractere, a notificação vai para
// um tópico que ninguém assina: não chega, e não gera erro em lugar nenhum.
//
// Os casos aqui são exatamente os de test/fcm_topics_test.dart. Os dois
// arquivos precisam concordar.
//
// Fica fora de functions/ de propósito: aquele diretório dispara deploy de
// produção no CI, e um teste não deve ser motivo para publicar function.

const assert = require('node:assert');
const {test} = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

/** Extrai a função sanitize do index.js sem carregar o módulo, que
 * inicializaria o Firebase Admin.
 * @return {function(string, string): string} a função sanitize do JS
 */
function loadSanitizeFromFunctions() {
  const src = fs.readFileSync(
      path.join(__dirname, '..', 'functions', 'index.js'), 'utf8');
  const start = src.indexOf('function sanitize(');
  assert.notStrictEqual(start, -1,
      'sanitize() não encontrada em functions/index.js — o teste de paridade ' +
      'precisa ser atualizado junto com o refactor.');
  // A função termina na primeira chave fechando na coluna zero.
  const end = src.indexOf('\n}', start);
  assert.notStrictEqual(end, -1, 'fim de sanitize() não localizado');
  const body = src.slice(start, end + 2);
  // eslint-disable-next-line no-new-func
  return new Function(`${body}; return sanitize;`)();
}

const sanitize = loadSanitizeFromFunctions();

// Espelho de test/fcm_topics_test.dart.
const cases = [
  ['producer', 'João Pedro', 'producer_joao_pedro'],
  ['team', 'Elétrica', 'team_eletrica'],
  ['team', 'Tapeçaria', 'team_tapecaria'],
  ['team', 'Comunicação Visual', 'team_comunicacao_visual'],
  ['leader', 'Ana   Maria', 'leader_ana_maria'],
  ['leader', 'Ana - Maria', 'leader_ana_maria'],
  ['consultant', '  Bruno  ', 'consultant_bruno'],
  ['consultant', '-Bruno-', 'consultant_bruno'],
  ['team', 'Equipe 2', 'team_equipe_2'],
  ['team', '', 'team_'],
  ['team', '   ', 'team_'],
];

test('sanitize do JS bate com o esperado pelo Dart', () => {
  for (const [prefix, raw, expected] of cases) {
    assert.strictEqual(sanitize(prefix, raw), expected,
        `sanitize("${prefix}", "${raw}")`);
  }
});

test('todas as equipes reais geram tópico aceito pelo FCM', () => {
  const teams = ['Limpeza', 'Elétrica', 'Marcenaria', 'Tapeçaria',
    'Vidraceiro', 'Comunicação Visual'];
  const valid = /^[a-zA-Z0-9\-_.~%]+$/;
  for (const t of teams) {
    assert.ok(valid.test(sanitize('team', t)), `tópico inválido para "${t}"`);
  }
});
