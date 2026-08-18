import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/utils/stand_street.dart';

/// A rua sai da localização do stand, e é ela que separa a OS da feira.
/// Errar aqui manda o entregador para a rua errada com o caminhão carregado.
void main() {
  group('rua a partir do stand', () {
    test('letra colada no número', () {
      expect(ruaDe('B50'), 'B');
      expect(ruaDe('A12'), 'A');
    });

    test('espaço entre a rua e o número', () {
      expect(ruaDe('A 12'), 'A');
    });

    test('rua com nome e separador', () {
      expect(ruaDe('RUA C - 3'), 'RUA C');
      expect(ruaDe('rua c-3'), 'RUA C');
    });

    test('caixa e espaço sobrando não criam ruas diferentes', () {
      expect(ruaDe(' b50 '), ruaDe('B50'));
    });

    test('stand só com número não ganha uma rua inventada', () {
      // Agrupar por uma rua que não existe juntaria stands sem relação
      // nenhuma na mesma folha.
      expect(ruaDe('50'), semRua);
      expect(ruaDe(''), semRua);
      expect(ruaDe('   '), semRua);
    });
  });

  group('ordem das ruas', () {
    test('alfabética, com a sobra no fim', () {
      final ruas = ['C', semRua, 'A', 'B']..sort(compararRuas);
      expect(ruas, ['A', 'B', 'C', semRua]);
    });
  });

  group('ordem dos stands dentro da rua', () {
    test('pelo número, não pelo texto', () {
      // Em ordem alfabética "B10" viria antes de "B9" e a lista impressa
      // mandaria a pessoa voltar no meio da rua.
      final stands = ['B10', 'B9', 'B2']..sort(compararStands);
      expect(stands, ['B2', 'B9', 'B10']);
    });

    test('stand sem número vai para o fim', () {
      final stands = ['B10', 'Externo', 'B2']..sort(compararStands);
      expect(stands.last, 'Externo');
    });
  });
}
