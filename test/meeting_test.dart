import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/models/meeting.dart';
import 'package:montagem_uset/services/directory_service.dart';

Meeting sample({DateTime? startsAt, List<AppUser>? participants}) => Meeting(
      id: 'm1',
      title: 'Alinhamento',
      fairId: 7,
      fairName: 'PET VET 2026',
      location: 'Sala 2',
      startsAt: startsAt ?? DateTime(2026, 8, 3, 14, 30),
      createdBy: 'Cleiton',
      createdAt: DateTime(2026, 8, 1, 9),
      participants: participants ??
          const [
            AppUser(name: 'Rosana', role: 'leader', team: 'Limpeza'),
            AppUser(name: 'Marcos', role: 'consultant'),
          ],
    );

void main() {
  group('ida e volta pelo Firestore', () {
    test('preserva os campos e os participantes', () {
      final m = sample();
      final volta = Meeting.fromFirestore('m1', m.toFirestore());
      expect(volta.title, m.title);
      expect(volta.fairId, m.fairId);
      expect(volta.fairName, m.fairName);
      expect(volta.location, m.location);
      expect(volta.participants.length, 2);
      expect(volta.participants.first.team, 'Limpeza');
    });

    test('o horário sobrevive à conversão para UTC e de volta', () {
      // A função de lembrete compara texto ISO com texto ISO. Se a gravação
      // e a leitura discordassem do fuso, o lembrete sairia na hora errada.
      final m = sample(startsAt: DateTime(2026, 8, 3, 14, 30));
      final volta = Meeting.fromFirestore('m1', m.toFirestore());
      expect(volta.startsAt, m.startsAt);
    });

    test('grava startsAt em UTC', () {
      final iso = sample().toFirestore()['startsAt'] as String;
      expect(iso.endsWith('Z'), isTrue,
          reason: 'sem o Z a função lê o horário como se fosse UTC');
    });

    test('documento incompleto não derruba a tela', () {
      final m = Meeting.fromFirestore('x', {});
      expect(m.title, '');
      expect(m.participants, isEmpty);
      expect(m.canceled, isFalse);
    });

    test('participante sem nome é descartado', () {
      final m = Meeting.fromFirestore('x', {
        'participants': [
          {'name': '', 'role': 'leader'},
          {'name': 'Ana', 'role': 'producer'},
        ],
      });
      expect(m.participants.map((p) => p.name), ['Ana']);
    });
  });

  group('includes', () {
    test('reconhece o convidado ignorando caixa e espaço', () {
      expect(sample().includes('  rosana ', 'leader'), isTrue);
    });

    test('mesmo nome em outro papel não está convidado', () {
      expect(sample().includes('Rosana', 'analyst'), isFalse);
    });

    test('quem não foi convidado não aparece', () {
      expect(sample().includes('Fulano', 'producer'), isFalse);
    });
  });

  group('isPast', () {
    test('reunião do passado', () {
      expect(sample(startsAt: DateTime(2020, 1, 1)).isPast, isTrue);
    });

    test('reunião do futuro', () {
      expect(
          sample(startsAt: DateTime.now().add(const Duration(hours: 2)))
              .isPast,
          isFalse);
    });
  });
}
