import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/models/client.dart';

Client stand({String produtor = 'Cleiton', List<String> pool = const []}) =>
    Client(
      rowId: '1_5',
      firestoreId: 'f5',
      nome: 'PINTA MUNDI',
      montagem: '19 a 22/06',
      local: '35B',
      hangar: 'A',
      area: '30',
      deck: '',
      totalArea: '30',
      mezanino: '',
      produtor: produtor,
      produtores: pool,
      marceneiro: '',
      tapeceiro: '',
      eletricista: '',
      faxineira: '',
      teto50: '',
    );

void main() {
  group('temProdutor', () {
    test('o segundo produtor também responde pelo stand', () {
      // O caso que motivou a mudança: o principal ficou sem bateria e
      // ninguém mais enxergava as pendências.
      final c = stand(produtor: 'Cleiton', pool: ['Cleiton', 'Ana Paula']);
      expect(c.temProdutor('Cleiton'), isTrue);
      expect(c.temProdutor('Ana Paula'), isTrue);
    });

    test('ignora caixa e espaço', () {
      final c = stand(pool: ['Cleiton', 'Ana Paula']);
      expect(c.temProdutor('  ana paula '), isTrue);
    });

    test('quem não está no grupo não responde', () {
      final c = stand(pool: ['Cleiton', 'Ana Paula']);
      expect(c.temProdutor('Fulano'), isFalse);
    });

    test('nome vazio nunca responde', () {
      expect(stand(pool: ['Cleiton']).temProdutor('   '), isFalse);
    });

    test('stand de um produtor só continua funcionando', () {
      // A coluna sem vírgula não preenche a lista; o campo produtor sozinho
      // precisa continuar valendo.
      final c = stand(produtor: 'Cleiton', pool: const []);
      expect(c.temProdutor('Cleiton'), isTrue);
      expect(c.temProdutor('Ana'), isFalse);
    });
  });

  group('chave de busca no banco', () {
    test('vai junto no toMap, para o banco poder procurar', () {
      final m = stand(pool: ['Cleiton', 'Ana Paula']).toMap();
      expect(m['produtores_key'], ',cleiton,ana paula,');
      expect(m['produtores'], 'Cleiton, Ana Paula');
    });
  });
}
