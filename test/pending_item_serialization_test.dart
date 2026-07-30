import 'package:flutter_test/flutter_test.dart';
import 'package:montagem_uset/models/pending_item.dart';

/// Ida e volta da pendência entre SQLite e Firestore.
///
/// Os campos novos (nota da montadora, fotos da manutenção, consultor) já
/// causaram perda silenciosa por não estarem em todos os mapeamentos: um
/// campo esquecido no toMap/fromMap simplesmente some no próximo sync, sem
/// erro nenhum.
void main() {
  final full = PendingItem(
    id: 7,
    firestoreId: 'abc123',
    clientId: '2_15',
    clientName: 'Acme',
    producerName: 'Amanda',
    consultantName: 'Bruno',
    local: 'B50',
    hangar: '2',
    team: 'Marcenaria',
    responsible: 'Carlos',
    description: 'Porta emperrada',
    photoUrls: const ['https://x/1.jpg', 'https://x/2.jpg'],
    origem: 'organizadora',
    createdBy: 'Organizadora: Fulana',
    resolvedBy: 'Administrador',
    approvalStatus: 'aprovada',
    rejectionReason: '',
    approvalNote: 'liberado',
    resolutionNote: 'dobradiça trocada',
    resolutionPhotoUrls: const ['https://x/done.jpg'],
    isResolved: true,
    awaitingValidation: false,
    inProgress: false,
    inProgressBy: '',
    createdAt: DateTime(2026, 7, 20, 14, 30),
    resolvedAt: DateTime(2026, 7, 20, 18, 45),
  );

  group('SQLite (toMap / fromMap)', () {
    test('preserva todos os campos na ida e volta', () {
      final back = PendingItem.fromMap(full.toMap());

      expect(back.clientId, full.clientId);
      expect(back.producerName, full.producerName);
      expect(back.consultantName, full.consultantName);
      expect(back.team, full.team);
      expect(back.responsible, full.responsible);
      expect(back.description, full.description);
      expect(back.photoUrls, full.photoUrls);
      expect(back.origem, full.origem);
      expect(back.createdBy, full.createdBy);
      expect(back.resolvedBy, full.resolvedBy);
      expect(back.approvalStatus, full.approvalStatus);
      expect(back.approvalNote, full.approvalNote);
      expect(back.resolutionNote, full.resolutionNote);
      expect(back.resolutionPhotoUrls, full.resolutionPhotoUrls);
      expect(back.isResolved, full.isResolved);
      expect(back.createdAt, full.createdAt);
      expect(back.resolvedAt, full.resolvedAt);
    });

    test('linha antiga sem as colunas novas não quebra', () {
      // Aparelho que ainda não migrou, ou registro anterior aos campos.
      final legacy = <String, dynamic>{
        'client_id': '1_1',
        'client_name': 'Antigo',
        'team': 'Limpeza',
        'description': 'algo',
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
      };
      final parsed = PendingItem.fromMap(legacy);

      expect(parsed.consultantName, '');
      expect(parsed.approvalNote, '');
      expect(parsed.resolutionNote, '');
      expect(parsed.resolutionPhotoUrls, isEmpty);
      expect(parsed.approvalStatus, 'none');
      expect(parsed.isResolved, isFalse);
    });
  });

  group('Firestore (fromFirestore)', () {
    test('lê os campos novos', () {
      final parsed = PendingItem.fromFirestore('doc1', {
        'clientId': '2_15',
        'clientName': 'Acme',
        'producerName': 'Amanda',
        'consultantName': 'Bruno',
        'team': 'Marcenaria',
        'description': 'Porta emperrada',
        'photoUrls': ['https://x/1.jpg'],
        'approvalStatus': 'recusada',
        'rejectionReason': 'não procede',
        'approvalNote': 'nota',
        'resolutionNote': 'reparo',
        'resolutionPhotoUrls': ['https://x/done.jpg'],
        'isResolved': true,
        'createdAt': DateTime(2026, 7, 20).toIso8601String(),
      });

      expect(parsed.firestoreId, 'doc1');
      expect(parsed.consultantName, 'Bruno');
      expect(parsed.rejectionReason, 'não procede');
      expect(parsed.resolutionNote, 'reparo');
      expect(parsed.resolutionPhotoUrls, ['https://x/done.jpg']);
      // Recusado, mesmo vindo com isResolved true.
      expect(parsed.isRejected, isTrue);
    });

    test('documento incompleto não lança', () {
      final parsed = PendingItem.fromFirestore('doc2', {'clientId': '1_1'});
      expect(parsed.clientName, '');
      expect(parsed.photoUrls, isEmpty);
      expect(parsed.resolutionPhotoUrls, isEmpty);
    });
  });

  group('fotos', () {
    test('aceita lista e JSON, e trata vazio', () {
      // SQLite guarda JSON; Firestore guarda lista nativa.
      expect(
          PendingItem.fromMap({
            'client_id': '1_1',
            'team': 't',
            'description': 'd',
            'created_at': DateTime(2026).toIso8601String(),
            'photo_urls': '["a","b"]',
          }).photoUrls,
          ['a', 'b']);

      expect(
          PendingItem.fromFirestore('d', {
            'clientId': '1_1',
            'photoUrls': ['a', 'b'],
            'createdAt': DateTime(2026).toIso8601String(),
          }).photoUrls,
          ['a', 'b']);

      expect(
          PendingItem.fromMap({
            'client_id': '1_1',
            'team': 't',
            'description': 'd',
            'created_at': DateTime(2026).toIso8601String(),
            'photo_urls': '',
          }).photoUrls,
          isEmpty);
    });
  });
}
