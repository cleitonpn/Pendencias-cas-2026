import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/models/pending_item.dart';
import 'package:montagem_uset/widgets/pending_status.dart';

/// Regras de situação da pendência.
///
/// Recusar um chamado grava `is_resolved = 1` JUNTO com
/// `approval_status = 'recusada'`. Foi essa sobreposição que gerou quatro
/// bugs em produção — recusados aparecendo como resolvidos no quadro, nos
/// relatórios, nas contagens e no relatório de entrega do stand. Estes testes
/// travam a precedência para que a regressão não passe de novo.
PendingItem item({
  String approvalStatus = 'none',
  bool isResolved = false,
  bool awaitingValidation = false,
  String rejectionReason = '',
  String approvalNote = '',
  String resolutionNote = '',
  List<String> resolutionPhotoUrls = const [],
}) =>
    PendingItem(
      clientId: '1_1',
      clientName: 'Cliente',
      local: 'A1',
      hangar: '1',
      team: 'Elétrica',
      description: 'desc',
      approvalStatus: approvalStatus,
      isResolved: isResolved,
      awaitingValidation: awaitingValidation,
      rejectionReason: rejectionReason,
      approvalNote: approvalNote,
      resolutionNote: resolutionNote,
      resolutionPhotoUrls: resolutionPhotoUrls,
      createdAt: DateTime(2026, 7, 1),
    );

void main() {
  group('statusOf', () {
    test('recusado tem precedência sobre resolvido', () {
      // O caso que quebrou: a recusa marca isResolved = true.
      final i = item(approvalStatus: 'recusada', isResolved: true);
      expect(statusOf(i).label, 'Recusado');
    });

    test('aguardando aprovação não é confundido com pendente comum', () {
      expect(statusOf(item(approvalStatus: 'pendente')).label,
          'Aguardando aprovação');
    });

    test('resolvido sem recusa é resolvido', () {
      expect(statusOf(item(isResolved: true)).label, 'Resolvido');
    });

    test('aguardando validação só vale se ainda não resolvido', () {
      expect(statusOf(item(awaitingValidation: true)).label,
          'Aguardando validação');
      // Depois de validado, resolvido vence.
      expect(statusOf(item(awaitingValidation: true, isResolved: true)).label,
          'Resolvido');
    });

    test('sem nada marcado é pendente', () {
      expect(statusOf(item()).label, 'Pendente');
    });

    test('aprovada e resolvida não vira recusada', () {
      expect(statusOf(item(approvalStatus: 'aprovada', isResolved: true)).label,
          'Resolvido');
    });
  });

  group('isRejected / isPendingApproval', () {
    test('reconhecem exatamente os valores gravados pelo app', () {
      expect(item(approvalStatus: 'recusada').isRejected, isTrue);
      expect(item(approvalStatus: 'pendente').isPendingApproval, isTrue);
      expect(item(approvalStatus: 'aprovada').isRejected, isFalse);
      expect(item(approvalStatus: 'none').isPendingApproval, isFalse);
    });
  });

  group('hasNotes', () {
    test('falso quando não há nenhuma anotação', () {
      expect(item().hasNotes, isFalse);
    });

    test('verdadeiro para qualquer uma das anotações, isolada', () {
      expect(item(approvalNote: 'ok').hasNotes, isTrue);
      expect(item(resolutionNote: 'trocado').hasNotes, isTrue);
      expect(item(rejectionReason: 'não procede').hasNotes, isTrue);
      expect(item(resolutionPhotoUrls: ['u']).hasNotes, isTrue);
    });
  });
}
