import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/utils/organizer_fairs.dart';

void main() {
  group('organizerFairIdsFrom', () {
    test('lê a lista nova', () {
      expect(organizerFairIdsFrom([3, 7, 9], null), [3, 7, 9]);
    });

    test('cai no campo antigo quando não há lista', () {
      expect(organizerFairIdsFrom(null, 5), [5]);
    });

    test('a lista manda quando os dois existem', () {
      // O campo antigo continua gravado com a primeira da lista, para os
      // aparelhos que ainda não atualizaram. Se ele fosse somado aqui, a
      // primeira feira apareceria duplicada.
      expect(organizerFairIdsFrom([4, 8], 4), [4, 8]);
    });

    test('aceita números em texto, dos dois lados', () {
      expect(organizerFairIdsFrom(['2', '6'], null), [2, 6]);
      expect(organizerFairIdsFrom(null, '11'), [11]);
    });

    test('sem vínculo devolve lista vazia', () {
      expect(organizerFairIdsFrom(null, null), isEmpty);
      expect(organizerFairIdsFrom(<Object>[], null), isEmpty);
    });

    test('descarta lixo em vez de estourar', () {
      expect(organizerFairIdsFrom([1, 'abc', null, 2], null), [1, 2]);
    });

    test('não repete id', () {
      expect(organizerFairIdsFrom([3, 3, '3'], null), [3]);
    });
  });
}
