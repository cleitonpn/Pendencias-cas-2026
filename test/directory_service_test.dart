import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/services/directory_service.dart';

void main() {
  final todos = [
    const AppUser(name: 'Cleiton', role: 'producer'),
    const AppUser(name: 'Ana Paula', role: 'producer'),
    const AppUser(name: 'Rosana', role: 'leader', team: 'Limpeza'),
    const AppUser(name: 'Marcos', role: 'consultant'),
    const AppUser(name: 'Julia', role: 'analyst'),
    const AppUser(name: 'Bia', role: 'manager'),
  ];

  group('match entre planilha e cadastro', () {
    test('acha ignorando caixa e espaço', () {
      // O nome da planilha é digitado à mão; o do cadastro vem do login.
      // Comparar o texto cru deixaria a pessoa fora do aviso em silêncio.
      final r = DirectoryService.match(
          todos, 'producer', ['  cleiton ', 'ANA PAULA']);
      expect(r.map((u) => u.name), ['Cleiton', 'Ana Paula']);
    });

    test('não mistura papéis', () {
      // "Rosana" é líder. Procurada como produtora, não pode aparecer.
      expect(DirectoryService.match(todos, 'producer', ['Rosana']), isEmpty);
      expect(DirectoryService.match(todos, 'leader', ['Rosana']).length, 1);
    });

    test('quem não tem cadastro simplesmente não volta', () {
      expect(DirectoryService.match(todos, 'producer', ['Fulano']), isEmpty);
    });

    test('nome vazio na planilha não casa com ninguém', () {
      expect(DirectoryService.match(todos, 'producer', ['', '   ']), isEmpty);
    });
  });

  group('papéis que entram sempre', () {
    test('analista, gerente e admin', () {
      expect(DirectoryService.alwaysIncluded,
          containsAll(['analyst', 'manager', 'admin']));
    });

    test('produtor, consultor e líder NÃO entram sempre', () {
      // Eles entram por trabalharem na feira. Se estivessem na lista fixa, o
      // aviso "por feira" iria para a empresa inteira.
      for (final r in ['producer', 'consultant', 'leader']) {
        expect(DirectoryService.alwaysIncluded.contains(r), isFalse,
            reason: '$r não pode receber aviso de feira em que não trabalha');
      }
    });

    test('todos os papéis fixos existem na lista de papéis', () {
      for (final r in DirectoryService.alwaysIncluded) {
        expect(DirectoryService.roles.contains(r), isTrue);
      }
    });
  });

  group('AppUser', () {
    test('a chave separa pessoas de mesmo nome em papéis diferentes', () {
      const a = AppUser(name: 'Rosana', role: 'leader');
      const b = AppUser(name: 'Rosana', role: 'analyst');
      expect(a.key == b.key, isFalse);
    });

    test('vai para o Firestore com nome, papel e equipe', () {
      const u = AppUser(name: 'Rosana', role: 'leader', team: 'Limpeza');
      expect(u.toMap(),
          {'name': 'Rosana', 'role': 'leader', 'team': 'Limpeza'});
    });
  });
}
