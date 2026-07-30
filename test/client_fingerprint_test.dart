import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/models/client.dart';
import 'package:montagem_uset/utils/client_fingerprint.dart';

Client base({
  int fairId = 1,
  String rowId = '1_5',
  String produtor = 'Cleiton',
  String nome = 'PINTA MUNDI',
  String local = '35B',
  bool isCompleted = false,
}) =>
    Client(
      fairId: fairId,
      rowId: rowId,
      firestoreId: 'abf_expo_5',
      nome: nome,
      montagem: '19 a 22/06',
      local: local,
      hangar: 'A',
      area: '30',
      deck: '',
      totalArea: '30',
      mezanino: '',
      produtor: produtor,
      marceneiro: '',
      tapeceiro: '',
      eletricista: '',
      faxineira: '',
      teto50: '',
      isCompleted: isCompleted,
      completedAt: isCompleted ? DateTime(2026, 7, 1) : null,
    );

void main() {
  group('o que muda a assinatura', () {
    test('mudar um dado da planilha muda', () {
      expect(clientFingerprint(base()) == clientFingerprint(base(produtor: 'Ana')),
          isFalse);
    });

    test('mudar o nome do stand muda', () {
      expect(clientFingerprint(base()) == clientFingerprint(base(nome: 'VOLTTA')),
          isFalse);
    });
  });

  group('o que NÃO pode mudar a assinatura', () {
    test('o id local da feira', () {
      // Cada aparelho numera as feiras do seu jeito. Se isso contasse, cada
      // um veria o do outro como alteração e reescreveria a planilha inteira
      // no Firestore, num pinga-pinga sem fim.
      expect(clientFingerprint(base(fairId: 1)),
          clientFingerprint(base(fairId: 99)));
    });

    test('o row_id, que carrega o id local da feira', () {
      expect(clientFingerprint(base(rowId: '1_5')),
          clientFingerprint(base(rowId: '99_5')));
    });

    test('o check-off do stand', () {
      // Concluir um stand não é alteração da planilha: isso mora em
      // client_status. Se contasse, marcar um stand publicaria a linha
      // inteira de novo.
      expect(clientFingerprint(base(isCompleted: false)),
          clientFingerprint(base(isCompleted: true)));
    });
  });

  group('estabilidade', () {
    test('o mesmo cliente dá sempre a mesma assinatura', () {
      expect(clientFingerprint(base()), clientFingerprint(base()));
    });

    test('campos vizinhos não se confundem', () {
      // Sem separador entre campos, "ab"+"c" e "a"+"bc" colidiriam e uma
      // alteração real passaria despercebida.
      expect(
          clientFingerprint(base(nome: 'ab', local: 'c')) ==
              clientFingerprint(base(nome: 'a', local: 'bc')),
          isFalse);
    });
  });
}
