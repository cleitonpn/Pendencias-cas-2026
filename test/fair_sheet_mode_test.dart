import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/models/fair.dart';

/// Os portais públicos montam a Fair a partir do documento do Firestore, com
/// um construtor próprio em cada tela. Quando esse construtor esquecia o
/// `sheetMode`, toda feira virava 'individual' — e a busca de expositores de
/// uma feira derivada trazia a planilha mestra inteira, com os expositores de
/// todas as feiras. Foi exatamente esse o vazamento na COP e na ABAV.
Fair fairFrom(Map<String, dynamic> m) => Fair(
      id: m['id'] as int?,
      name: (m['name'] as String?) ?? '',
      spreadsheetId: (m['spreadsheetId'] as String?) ?? '',
      sheetName: (m['sheetName'] as String?) ?? '',
      createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ??
          DateTime(2026),
      mode: (m['mode'] as String?) ?? 'producao',
      sheetMode: (m['sheetMode'] as String?) ?? 'individual',
    );

void main() {
  group('sheetMode vindo do Firestore', () {
    test('feira derivada é reconhecida como filha da mestra', () {
      final f = fairFrom({
        'id': 42,
        'name': 'COP INTERNACIONAL',
        'spreadsheetId': 'abc',
        'sheetName': 'projetos',
        'sheetMode': 'mestra_child',
      });
      expect(f.isMestraChild, isTrue);
      expect(f.isMestra, isFalse);
    });

    test('a mestra é reconhecida como guarda-chuva, não como feira', () {
      final f = fairFrom({'id': 1, 'name': 'OPERACIONAL', 'sheetMode': 'mestra'});
      expect(f.isMestra, isTrue);
      expect(f.isMestraChild, isFalse);
    });

    test('sem sheetMode no documento, vale planilha própria', () {
      final f = fairFrom({'id': 2, 'name': 'PET VET 2026'});
      expect(f.isMestra, isFalse);
      expect(f.isMestraChild, isFalse);
    });
  });

  group('padrão do modelo', () {
    test('uma feira nova não nasce como mestra nem como derivada', () {
      final f = Fair(
          id: 3,
          name: 'X',
          spreadsheetId: 's',
          sheetName: 'a',
          createdAt: DateTime(2026));
      expect(f.isMestra, isFalse);
      expect(f.isMestraChild, isFalse);
    });

    test('sheet_mode sobrevive à ida e volta do banco', () {
      final f = Fair(
          id: 4,
          name: 'Y',
          spreadsheetId: 's',
          sheetName: 'a',
          createdAt: DateTime(2026),
          sheetMode: 'mestra_child');
      expect(Fair.fromMap(f.toMap()).isMestraChild, isTrue);
    });
  });
}
