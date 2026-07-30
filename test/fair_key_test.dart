import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/utils/fair_key.dart';

void main() {
  group('fairKey', () {
    test('ignora maiúsculas, espaço sobrando e acento', () {
      // O nome vem digitado à mão na coluna FEIRA da planilha mestra e muda
      // de uma sincronização para a outra. Se a chave mudasse junto, a feira
      // excluída voltaria na primeira redigitação.
      expect(fairKey('  Expo Católica '), fairKey('EXPO CATOLICA'));
      expect(fairKey('Festival Interlagos'), fairKey('FESTIVAL  INTERLAGOS'));
    });

    test('serve como id de documento — só letras, números e sublinhado', () {
      expect(fairKey('COP / Internacional 2026'), 'cop_internacional_2026');
      expect(fairKey('AB CASA'), 'ab_casa');
    });

    test('não deixa sublinhado sobrando nas pontas', () {
      expect(fairKey('  ---ABAV---  '), 'abav');
    });

    test('feiras diferentes continuam diferentes', () {
      expect(fairKey('ABF EXPO') == fairKey('ABAV'), isFalse);
      expect(fairKey('SOGESP') == fairKey('FISA'), isFalse);
    });

    test('nome vazio vira chave vazia', () {
      expect(fairKey('   '), '');
    });
  });
}
