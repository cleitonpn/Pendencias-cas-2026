// Paridade entre as coleções de PIN e as regras do Firestore.
//
// Toda coleção usada como fonte de PIN precisa estar fechada para o cliente
// em firestore.rules. Se alguém acrescentar um papel novo em PIN_SOURCES e
// esquecer a regra, aquela coleção volta a ser legível por qualquer sessão
// autenticada — inclusive a anônima dos portais públicos — e nada quebra:
// o app continua funcionando, só que com os PINs expostos de novo.
//
// É a mesma classe de falha silenciosa da paridade dos tópicos FCM, e por
// isso mora no mesmo lugar: fora de functions/, que dispara deploy no CI.

const assert = require('node:assert');
const {test} = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');

/** Coleções declaradas em PIN_SOURCES, lidas do texto do index.js.
 * @return {string[]} nomes das coleções
 */
function pinCollections() {
  const src = fs.readFileSync(path.join(root, 'functions/index.js'), 'utf8');
  const start = src.indexOf('const PIN_SOURCES = {');
  assert.ok(start >= 0, 'PIN_SOURCES não encontrado em functions/index.js');
  const end = src.indexOf('};', start);
  const block = src.slice(start, end);
  return [...block.matchAll(/collection:\s*"([^"]+)"/g)].map((m) => m[1]);
}

/** Coleções bloqueadas em isProtected(), lidas do texto das regras.
 * @return {string[]} nomes das coleções
 */
function protectedCollections() {
  const src = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  const start = src.indexOf('function isProtected(');
  assert.ok(start >= 0, 'isProtected não encontrado em firestore.rules');
  const end = src.indexOf('}', src.indexOf('return', start));
  const block = src.slice(start, end);
  return [...block.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
}

test('toda coleção de PIN está fechada nas regras', () => {
  const pins = pinCollections();
  const blocked = protectedCollections();

  assert.ok(pins.length >= 8, `esperava 8+ fontes de PIN, achei ${pins.length}`);

  for (const col of pins) {
    assert.ok(
        blocked.includes(col),
        `${col} é fonte de PIN mas não está em isProtected() de ` +
        'firestore.rules — os PINs desse papel ficam expostos ao cliente',
    );
  }
});

test('a coleção de sessões de admin está fechada', () => {
  assert.ok(
      protectedCollections().includes('admin_sessions'),
      'admin_sessions precisa estar fechada: um token vazado dá acesso ' +
      'total à gestão de usuários',
  );
});

test('o contador de tentativas está fechado', () => {
  assert.ok(
      protectedCollections().includes('pin_attempts'),
      'pin_attempts precisa estar fechada: se o cliente puder apagar o ' +
      'próprio contador, o freio de força bruta não vale nada',
  );
});

test('app_config é somente leitura para o cliente', () => {
  const src = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  const start = src.indexOf('function isServerOwned(');
  assert.ok(start >= 0, 'isServerOwned não encontrado em firestore.rules');
  const end = src.indexOf('}', src.indexOf('return', start));
  assert.ok(
      src.slice(start, end).includes("'app_config'"),
      'app_config precisa ser somente leitura: com escrita liberada, ' +
      'qualquer sessão autenticada tranca a equipe fora do app definindo ' +
      'uma versão mínima inexistente',
  );
  // A regra tem de separar leitura de escrita; um `allow read, write` junto
  // devolveria a escrita ao cliente sem ninguém notar.
  assert.ok(
      /allow read:/.test(src) && /allow write:/.test(src),
      'as permissões de leitura e escrita precisam estar separadas',
  );
});

test('a regra geral não usa o curinga recursivo', () => {
  const src = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  const rules = src.split('\n')
      .filter((l) => !l.trim().startsWith('//'))
      .join('\n');
  // As regras somam com OU: um match /{document=**} liberado autorizaria as
  // coleções de PIN mesmo com o match específico negando.
  assert.ok(
      !rules.includes('{document=**}'),
      'firestore.rules voltou a usar {document=**}, o que anula o bloqueio ' +
      'das coleções de PIN',
  );
});
