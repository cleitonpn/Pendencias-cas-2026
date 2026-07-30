import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/utils/fcm_topics.dart';

/// O sanitizador de tópicos existe DUAS vezes: aqui em Dart e em
/// functions/index.js. O app assina o tópico com a versão Dart e a Cloud
/// Function publica com a versão JS — se as duas divergirem em um único
/// caractere, a notificação é enviada para um tópico que ninguém assina e
/// simplesmente não chega, sem erro em lugar nenhum.
///
/// Estes casos são os mesmos verificados contra a implementação JS em
/// test/fcm_topics_parity_test.js, executado no CI.
void main() {
  group('fcmTopic', () {
    test('minúsculas e espaços viram sublinhado', () {
      expect(fcmTopic('producer', 'João Pedro'), 'producer_joao_pedro');
    });

    test('remove acentos e cedilha', () {
      expect(fcmTopic('team', 'Elétrica'), 'team_eletrica');
      expect(fcmTopic('team', 'Tapeçaria'), 'team_tapecaria');
      expect(fcmTopic('team', 'Comunicação Visual'),
          'team_comunicacao_visual');
    });

    test('agrupa separadores seguidos num único sublinhado', () {
      expect(fcmTopic('leader', 'Ana   Maria'), 'leader_ana_maria');
      expect(fcmTopic('leader', 'Ana - Maria'), 'leader_ana_maria');
    });

    test('apara sublinhados das pontas', () {
      expect(fcmTopic('consultant', '  Bruno  '), 'consultant_bruno');
      expect(fcmTopic('consultant', '-Bruno-'), 'consultant_bruno');
    });

    test('mantém números', () {
      expect(fcmTopic('team', 'Equipe 2'), 'team_equipe_2');
    });

    test('nome vazio não gera tópico malformado', () {
      expect(fcmTopic('team', ''), 'team_');
      expect(fcmTopic('team', '   '), 'team_');
    });

    test('todas as equipes reais produzem tópico válido para o FCM', () {
      // FCM aceita [a-zA-Z0-9-_.~%]+ — o sanitizador precisa garantir isso.
      const teams = [
        'Limpeza',
        'Elétrica',
        'Marcenaria',
        'Tapeçaria',
        'Vidraceiro',
        'Comunicação Visual',
      ];
      final valid = RegExp(r'^[a-zA-Z0-9\-_.~%]+$');
      for (final t in teams) {
        expect(valid.hasMatch(fcmTopic('team', t)), isTrue,
            reason: 'tópico inválido para "$t"');
      }
    });
  });
}
