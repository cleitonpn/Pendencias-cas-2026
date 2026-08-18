import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/utils/analyst_notes.dart';

/// As considerações são de PESSOAS. O formato antigo guardava uma só por
/// stand, então quem escrevesse depois gravava por cima e a observação do
/// primeiro sumia — sem aviso, e sem ele saber. Estes testes cuidam de que
/// nenhuma anotação desapareça na leitura.
void main() {
  group('lista de considerações', () {
    test('devolve todas, da mais nova para a mais antiga', () {
      final notas = analystNotesFrom({
        'notes': [
          {'id': 'a', 'text': 'primeira', 'at': '2026-08-01T10:00:00.000'},
          {'id': 'b', 'text': 'segunda', 'at': '2026-08-02T10:00:00.000'},
        ],
      });
      expect(notas.map((n) => n['text']), ['segunda', 'primeira']);
    });

    test('a anotação de um não apaga a do outro', () {
      // O bug que originou a lista: dois analistas, uma caixa só.
      final notas = analystNotesFrom({
        'notes': [
          {'id': 'a', 'text': 'do Renan', 'by': 'Renan', 'at': '2026-08-01T10:00:00.000'},
          {'id': 'b', 'text': 'da Amanda', 'by': 'Amanda', 'at': '2026-08-01T11:00:00.000'},
        ],
      });
      expect(notas.length, 2);
      expect(notas.map((n) => n['by']).toSet(), {'Renan', 'Amanda'});
    });

    test('documento vazio ou ausente não quebra', () {
      expect(analystNotesFrom(null), isEmpty);
      expect(analystNotesFrom({}), isEmpty);
      expect(analystNotesFrom({'notes': []}), isEmpty);
    });

    test('item estranho no meio da lista não derruba os outros', () {
      final notas = analystNotesFrom({
        'notes': [
          'lixo',
          {'id': 'a', 'text': 'boa', 'at': '2026-08-01T10:00:00.000'},
        ],
      });
      expect(notas.single['text'], 'boa');
    });
  });

  group('consideração no formato antigo', () {
    test('continua aparecendo, e marcada como legado', () {
      // Ela vive no corpo do documento, nao no array. Se sumisse da leitura,
      // a mudanca teria causado exatamente a perda que veio impedir.
      final notas = analystNotesFrom({
        'text': 'escrita antes da lista existir',
        'link': 'https://x',
        'updatedBy': 'Cleiton',
        'updatedAt': '2026-07-01T09:00:00.000',
      });
      expect(notas.single['text'], 'escrita antes da lista existir');
      expect(notas.single['by'], 'Cleiton');
      expect(notas.single['id'], legadoId);
    });

    test('só o link, sem texto, também conta', () {
      final notas = analystNotesFrom({'link': 'https://x'});
      expect(notas.single['link'], 'https://x');
    });

    test('sobrevive quando alguém escreve uma anotação nova', () {
      // O campo antigo continua no documento depois da primeira anotação
      // nova. Se ele só aparecesse com a lista vazia, sumiria justamente no
      // momento em que a segunda pessoa escrevesse.
      final notas = analystNotesFrom({
        'text': 'antiga',
        'updatedAt': '2026-07-01T09:00:00.000',
        'notes': [
          {'id': 'a', 'text': 'nova', 'at': '2026-08-01T10:00:00.000'},
        ],
      });
      expect(notas.map((n) => n['text']), ['nova', 'antiga']);
    });

    test('não é duplicada depois de migrada para dentro da lista', () {
      final notas = analystNotesFrom({
        'text': 'antiga',
        'notes': [
          {'id': legadoId, 'text': 'antiga', 'at': '2026-07-01T09:00:00.000'},
        ],
      });
      expect(notas.length, 1);
    });

    test('documento sem texto nem lista não inventa anotação vazia', () {
      expect(analystNotesFrom({'updatedBy': 'Cleiton'}), isEmpty);
    });
  });
}
