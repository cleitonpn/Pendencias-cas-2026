import 'dart:convert';

class PendingItem {
  final int? id;               // SQLite local ID
  final String? firestoreId;   // Firestore document ID
  final String clientId;
  final String clientName;
  final String producerName;   // producer of this client (for Firestore queries)
  final String fairName;       // fair name (Firestore items); empty for SQLite
  final String local;
  final String hangar;
  final String team;
  final String responsible;
  final String description;
  final List<String> photoUrls; // download URLs of attached photos
  final String origem;          // 'equipe' (criada pela equipe) | 'cliente' (expositor via QR)
  bool isResolved;
  bool awaitingValidation;     // producer marked as done, admin needs to validate
  final DateTime createdAt;
  DateTime? resolvedAt;

  PendingItem({
    this.id,
    this.firestoreId,
    required this.clientId,
    required this.clientName,
    this.producerName = '',
    this.fairName = '',
    required this.local,
    required this.hangar,
    required this.team,
    this.responsible = '',
    required this.description,
    this.photoUrls = const [],
    this.origem = 'equipe',
    this.isResolved = false,
    this.awaitingValidation = false,
    required this.createdAt,
    this.resolvedAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        if (firestoreId != null) 'firestore_id': firestoreId,
        'client_id': clientId,
        'client_name': clientName,
        'producer_name': producerName,
        'local': local,
        'hangar': hangar,
        'team': team,
        'responsible': responsible,
        'description': description,
        'photo_urls': jsonEncode(photoUrls),
        'origem': origem,
        'is_resolved': isResolved ? 1 : 0,
        'awaiting_validation': awaitingValidation ? 1 : 0,
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
        fairName: '',
        local: map['local'] ?? map['stand'] ?? '',
        hangar: map['hangar'] ?? '',
        team: map['team'] as String,
        responsible: map['responsible'] ?? '',
        description: map['description'] as String,
        photoUrls: _parsePhotos(map['photo_urls']),
        origem: (map['origem'] as String?) ?? 'equipe',
        isResolved: (map['is_resolved'] as int? ?? 0) == 1,
        awaitingValidation: (map['awaiting_validation'] as int? ?? 0) == 1,
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
        fairName: data['fairName'] ?? '',
        local: data['local'] ?? '',
        hangar: data['hangar'] ?? '',
        team: data['team'] ?? '',
        responsible: data['responsible'] ?? '',
        description: data['description'] ?? '',
        photoUrls: _parsePhotos(data['photoUrls']),
        origem: (data['origem'] as String?) ?? 'equipe',
        isResolved: data['isResolved'] as bool? ?? false,
        awaitingValidation: data['awaitingValidation'] as bool? ?? false,
        createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ??
            DateTime.now(),
        resolvedAt: data['resolvedAt'] != null
            ? DateTime.tryParse(data['resolvedAt'] as String)
            : null,
      );

  bool get fromClient => origem == 'cliente';

  String toWhatsAppText() {
    final d = createdAt;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final respLine =
        responsible.isNotEmpty ? '\nResponsável: $responsible' : '';
    final location =
        hangar.isNotEmpty ? 'Hangar: $hangar | Stand: $local' : 'Stand: $local';
    return '*PENDÊNCIA*\n'
        '$location\n'
        'Cliente: $clientName\n'
        'Equipe: $team$respLine\n'
        'Pendência: $description\n'
        'Registrado: $dateStr';
  }
}
