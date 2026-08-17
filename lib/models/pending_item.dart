import '../utils/producer_pool.dart';
import '../utils/furniture_items.dart';
import 'dart:convert';

class PendingItem {
  final int? id;               // SQLite local ID
  final String? firestoreId;   // Firestore document ID
  final String clientId;
  final String clientName;
  final String producerName;   // producer of this client (for Firestore queries)

  /// Todos os produtores do stand. Com mais de um, os dois respondem pelo
  /// chamado e os dois precisam ser avisados — só o primeiro receber foi o
  /// que deixou a equipe sem enxergar as pendências quando o principal ficou
  /// sem bateria.
  final List<String> producerNames;
  final String consultantName; // atendimento do cliente — usado para notificar
                               // apenas quem está atrelado a ele
  final String fairName;       // fair name (Firestore items); empty for SQLite
  final String local;
  final String hangar;
  final String team;
  final String responsible;
  final String description;
  final List<String> photoUrls; // download URLs of attached photos

  /// Itens de mobiliário marcados no chamado, com a classificação que tinham
  /// na hora. Vazio em pendência de qualquer outra equipe.
  ///
  /// Existe para o problema não depender de digitação: "cadeira dkr" e
  /// "cadeira DKR" viravam duas coisas diferentes no relatório, e "o balcão
  /// está torto" não dizia QUAL balcão. Marcando na lista do stand, dá para
  /// contar depois se o problema está mais do lado interno ou do sublocado.
  final List<FurniturePick> furnitureItems;
  final String origem;          // 'equipe' (criada pela equipe) | 'cliente' (expositor via QR) | 'organizadora'
  final String createdBy;       // quem registrou a pendência
  String resolvedBy;            // quem resolveu/validou
  // Fluxo de aprovação (só relevante para origem == 'organizadora'):
  // 'none' (não precisa de aprovação) | 'pendente' | 'aprovada' | 'recusada'
  String approvalStatus;
  String rejectionReason;       // motivo da recusa pelo atendimento
  String approvalNote;          // nota opcional deixada ao aprovar o chamado
  String resolutionNote;        // nota de manutenção deixada ao concluir
  List<String> resolutionPhotoUrls; // fotos da manutenção feita
  bool isResolved;
  bool awaitingValidation;     // producer marked as done, admin needs to validate

  /// Quem EXECUTOU o serviço, e quando.
  ///
  /// Diferente de resolvedBy, que registra quem validou. No fluxo normal o
  /// produtor marca como feito e o admin valida — e era o admin que ficava
  /// gravado, então o ranking creditava "Administrador" por todo o trabalho
  /// de campo.
  String executedBy;
  DateTime? executedAt;
  bool inProgress;
  String inProgressBy;
  final DateTime createdAt;
  DateTime? resolvedAt;

  PendingItem({
    this.id,
    this.firestoreId,
    required this.clientId,
    required this.clientName,
    this.producerName = '',
    this.producerNames = const [],
    this.consultantName = '',
    this.fairName = '',
    required this.local,
    required this.hangar,
    required this.team,
    this.responsible = '',
    required this.description,
    this.photoUrls = const [],
    this.furnitureItems = const [],
    this.origem = 'equipe',
    this.createdBy = '',
    this.resolvedBy = '',
    this.approvalStatus = 'none',
    this.rejectionReason = '',
    this.approvalNote = '',
    this.resolutionNote = '',
    this.resolutionPhotoUrls = const [],
    this.isResolved = false,
    this.awaitingValidation = false,
    this.executedBy = '',
    this.executedAt,
    this.inProgress = false,
    this.inProgressBy = '',
    required this.createdAt,
    this.resolvedAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        if (firestoreId != null) 'firestore_id': firestoreId,
        'client_id': clientId,
        'client_name': clientName,
        'producer_name': producerName,
        'producer_names': producerNames.join(', '),
        'consultant_name': consultantName,
        'local': local,
        'hangar': hangar,
        'team': team,
        'responsible': responsible,
        'description': description,
        'photo_urls': jsonEncode(photoUrls),
        'furniture_items':
            jsonEncode(furnitureItems.map((f) => f.toMap()).toList()),
        'origem': origem,
        'created_by': createdBy,
        'resolved_by': resolvedBy,
        'approval_status': approvalStatus,
        'rejection_reason': rejectionReason,
        'approval_note': approvalNote,
        'resolution_note': resolutionNote,
        'resolution_photos': jsonEncode(resolutionPhotoUrls),
        'is_resolved': isResolved ? 1 : 0,
        'awaiting_validation': awaitingValidation ? 1 : 0,
        'executed_by': executedBy,
        'executed_at': executedAt?.toIso8601String(),
        'in_progress': inProgress ? 1 : 0,
        'in_progress_by': inProgressBy,
        'created_at': createdAt.toIso8601String(),
        'resolved_at': resolvedAt?.toIso8601String(),
      };

  static List<String> _parsePhotos(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    final s = raw.toString().trim();
    if (s.isEmpty) return const [];
    try {
      final decoded = jsonDecode(s);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }

  factory PendingItem.fromMap(Map<String, dynamic> map) => PendingItem(
        id: map['id'] as int?,
        firestoreId: map['firestore_id'] as String?,
        clientId: map['client_id'] as String,
        clientName: map['client_name'] ?? '',
        producerName: map['producer_name'] ?? '',
        producerNames: produtoresFrom((map['producer_names'] as String?) ?? ''),
        consultantName: map['consultant_name'] ?? '',
        fairName: '',
        local: map['local'] ?? map['stand'] ?? '',
        hangar: map['hangar'] ?? '',
        team: map['team'] as String,
        responsible: map['responsible'] ?? '',
        description: map['description'] as String,
        photoUrls: _parsePhotos(map['photo_urls']),
        furnitureItems: furniturePicksFrom(map['furniture_items']),
        origem: (map['origem'] as String?) ?? 'equipe',
        createdBy: (map['created_by'] as String?) ?? '',
        resolvedBy: (map['resolved_by'] as String?) ?? '',
        approvalStatus: (map['approval_status'] as String?) ?? 'none',
        rejectionReason: (map['rejection_reason'] as String?) ?? '',
        approvalNote: (map['approval_note'] as String?) ?? '',
        resolutionNote: (map['resolution_note'] as String?) ?? '',
        resolutionPhotoUrls: _parsePhotos(map['resolution_photos']),
        isResolved: (map['is_resolved'] as int? ?? 0) == 1,
        awaitingValidation: (map['awaiting_validation'] as int? ?? 0) == 1,
        executedBy: (map['executed_by'] as String?) ?? '',
        executedAt: DateTime.tryParse((map['executed_at'] as String?) ?? ''),
        inProgress: (map['in_progress'] as int? ?? 0) == 1,
        inProgressBy: (map['in_progress_by'] as String?) ?? '',
        createdAt: DateTime.parse(map['created_at'] as String),
        resolvedAt: map['resolved_at'] != null
            ? DateTime.tryParse(map['resolved_at'] as String)
            : null,
      );

  factory PendingItem.fromFirestore(
          String id, Map<String, dynamic> data) =>
      PendingItem(
        firestoreId: id,
        clientId: data['clientId'] ?? '',
        clientName: data['clientName'] ?? '',
        producerName: data['producerName'] ?? '',
        producerNames: ((data['producerNames'] as List?) ?? const [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList(),
        consultantName: data['consultantName'] ?? '',
        fairName: data['fairName'] ?? '',
        local: data['local'] ?? '',
        hangar: data['hangar'] ?? '',
        team: data['team'] ?? '',
        responsible: data['responsible'] ?? '',
        description: data['description'] ?? '',
        photoUrls: _parsePhotos(data['photoUrls']),
        furnitureItems: furniturePicksFrom(data['furnitureItems']),
        origem: (data['origem'] as String?) ?? 'equipe',
        createdBy: (data['createdBy'] as String?) ?? '',
        resolvedBy: (data['resolvedBy'] as String?) ?? '',
        approvalStatus: (data['approvalStatus'] as String?) ?? 'none',
        rejectionReason: (data['rejectionReason'] as String?) ?? '',
        approvalNote: (data['approvalNote'] as String?) ?? '',
        resolutionNote: (data['resolutionNote'] as String?) ?? '',
        resolutionPhotoUrls: _parsePhotos(data['resolutionPhotoUrls']),
        isResolved: data['isResolved'] as bool? ?? false,
        awaitingValidation: data['awaitingValidation'] as bool? ?? false,
        executedBy: (data['executedBy'] as String?) ?? '',
        executedAt: DateTime.tryParse((data['executedAt'] as String?) ?? ''),
        inProgress: data['inProgress'] as bool? ?? false,
        inProgressBy: (data['inProgressBy'] as String?) ?? '',
        createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ??
            DateTime.now(),
        resolvedAt: data['resolvedAt'] != null
            ? DateTime.tryParse(data['resolvedAt'] as String)
            : null,
      );

  /// Os móveis marcados em uma linha, prontos para entrar num texto. Vazio
  /// quando não há item marcado — quem usa decide se coloca colchete ou não.
  String get furnitureLabel =>
      furnitureItems.map((f) => f.raw).join(' | ');

  bool get fromClient => origem == 'cliente';
  bool get fromOrganizer => origem == 'organizadora';
  bool get isPendingApproval => approvalStatus == 'pendente';
  bool get isRejected => approvalStatus == 'recusada';

  /// Tem alguma anotação da montadora para exibir (aprovação, conclusão ou
  /// recusa), com ou sem fotos da manutenção.
  bool get hasNotes =>
      approvalNote.isNotEmpty ||
      resolutionNote.isNotEmpty ||
      rejectionReason.isNotEmpty ||
      resolutionPhotoUrls.isNotEmpty;

  String toWhatsAppText() {
    final d = createdAt;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final respLine =
        responsible.isNotEmpty ? '\nResponsável: $responsible' : '';
    final location =
        hangar.isNotEmpty ? 'Hangar: $hangar | Stand: $local' : 'Stand: $local';
    // Os itens vão no texto do WhatsApp porque é por ele que a equipe recebe o
    // chamado na prática. Sem isso, quem lê a mensagem continuaria sem saber
    // qual dos móveis do stand é o do problema.
    final itensLinha =
        furnitureItems.isEmpty ? '' : '\nItem: $furnitureLabel';
    return '*PENDÊNCIA*\n'
        '$location\n'
        'Cliente: $clientName\n'
        'Equipe: $team$respLine$itensLinha\n'
        'Pendência: $description\n'
        'Registrado: $dateStr';
  }
}
