// Implementação de REFERÊNCIA da clientKey, em JavaScript, mais o teste de
// paridade com a versão Dart.
//
// ─────────────────────────────────────────────────────────────────────────────
// PARA A FERRAMENTA DE APROVAÇÃO DE ARTE
//
// Copie `normalizeKeyPart` e `clientKeyFor` daqui VERBATIM. Não reescreva a
// partir da descrição: "minúsculas, sem acento, só [a-z0-9]" admite mais de uma
// implementação, e duas delas discordam.
//
// O ponto onde é fácil errar: acento é CONVERTIDO, não removido. "Módulos" tem
// de virar `modulos`. Se um lado apagar o caractere acentuado, ele produz
// `mdulos` e a ponte simplesmente não casa nada — sem erro em lugar nenhum,
// exatamente como aconteceu com os tópicos FCM antes deste tipo de teste
// existir.
//
// Rode este arquivo no CI de lá também (`node --test`). Se os dois repositórios
// passarem nos mesmos casos, as chaves batem.
// ─────────────────────────────────────────────────────────────────────────────
//
// Fica em tools/ e não em functions/ de propósito: aquele diretório dispara
// deploy de produção no CI, e um teste não deve ser motivo para publicar.

const assert = require('node:assert');
const {test} = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

const ACENTOS = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'ê': 'e', 'è': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

const SEPARADOR = '__';

/** Uma parte da chave: minúsculas, sem acento, resto vira "_".
 * @param {string} raw texto cru (nome da feira ou do expositor)
 * @return {string} parte normalizada, sem "_" nas pontas
 */
function normalizeKeyPart(raw) {
  let s = String(raw == null ? '' : raw).toLowerCase().trim();
  for (const [de, para] of Object.entries(ACENTOS)) {
    s = s.split(de).join(para);
  }
  return s.replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
}

/** A chave estável do expositor, ou "" quando não dá para formar uma.
 * @param {string} fairName nome da feira
 * @param {string} nome nome do expositor
 * @return {string} a chave, ou "" se faltar qualquer uma das partes
 */
function clientKeyFor(fairName, nome) {
  const f = normalizeKeyPart(fairName);
  const n = normalizeKeyPart(nome);
  if (!f || !n) return '';
  return f + SEPARADOR + n;
}

module.exports = {normalizeKeyPart, clientKeyFor, SEPARADOR};

// ─── Casos ───────────────────────────────────────────────────────────────────
//
// Espelho exato de test/client_key_test.dart. Os dois arquivos precisam
// concordar; mudar um sem o outro é o começo da divergência.

const CASOS = [
  // [fairName, nome, chave esperada]
  ['ABAV', 'JadLog', 'abav__jadlog'],
  ['ABAV', 'JADLOG', 'abav__jadlog'],
  ['ABAV', ' jadlog ', 'abav__jadlog'],
  // Acento CONVERTIDO, nunca apagado. Este é o caso que separa uma
  // implementação correta de uma que parece correta.
  ['CAS 2026 Módulos', 'Comunicação', 'cas_2026_modulos__comunicacao'],
  ['Conferencia Luxo — ECBR', 'J&T', 'conferencia_luxo_ecbr__j_t'],
  ['São Paulo', 'Açaí & Cia', 'sao_paulo__acai_cia'],
  // Pontuação seguida vira um "_" só, e não sobra nas pontas.
  ['  ABAV  ', '-- Selia --', 'abav__selia'],
  ['ABAV', 'Tray  Commerce', 'abav__tray_commerce'],
  // Sem uma das partes não há chave: meia chave ligaria coisas sem relação.
  ['', 'JadLog', ''],
  ['ABAV', '', ''],
  ['ABAV', '   ', ''],
  ['ABAV', '###', ''],
];

test('normalizeKeyPart converte acento em vez de apagar', () => {
  assert.strictEqual(normalizeKeyPart('Módulos'), 'modulos');
  assert.strictEqual(normalizeKeyPart('Comunicação'), 'comunicacao');
  assert.strictEqual(normalizeKeyPart('São Paulo'), 'sao_paulo');
});

test('normalizeKeyPart não deixa "_" nas pontas nem repetido', () => {
  assert.strictEqual(normalizeKeyPart('-- Selia --'), 'selia');
  assert.strictEqual(normalizeKeyPart('A  &&  B'), 'a_b');
});

test('clientKeyFor bate com os casos de referência', () => {
  for (const [feira, nome, esperado] of CASOS) {
    assert.strictEqual(clientKeyFor(feira, nome), esperado,
        `clientKeyFor(${JSON.stringify(feira)}, ${JSON.stringify(nome)})`);
  }
});

test('o separador nunca fica ambíguo', () => {
  // Nenhuma parte normalizada contém "__", então "feira_a" + "b" não pode
  // colidir com "feira" + "a_b".
  assert.notStrictEqual(
      clientKeyFor('feira a', 'b'), clientKeyFor('feira', 'a b'));
});

// ─── Paridade com o Dart ─────────────────────────────────────────────────────

test('os casos daqui existem iguais no teste Dart', () => {
  const dart = fs.readFileSync(
      path.join(__dirname, '..', 'test', 'client_key_test.dart'), 'utf8');
  for (const [feira, nome, esperado] of CASOS) {
    if (esperado === '') continue; // os vazios são verificados à parte lá
    assert.ok(dart.includes(`'${esperado}'`),
        `o caso "${esperado}" (${feira} / ${nome}) não está em ` +
        'test/client_key_test.dart — os dois lados precisam testar o mesmo.');
  }
});

test('a tabela de acentos do Dart e a daqui são a mesma', () => {
  const dart = fs.readFileSync(
      path.join(__dirname, '..', 'lib', 'utils', 'client_key.dart'), 'utf8');
  for (const [de, para] of Object.entries(ACENTOS)) {
    assert.ok(dart.includes(`'${de}': '${para}'`),
        `o acento ${de}→${para} está no JS e não em lib/utils/client_key.dart`);
  }
});
