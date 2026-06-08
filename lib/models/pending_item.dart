class PendingItem {
  final int? id;               // SQLite local ID
  final String? firestoreId;   // Firestore document ID
  final String clientId;
  final String clientName;
  final String producerName;   // producer of this client (for Firestore queries)
  final String local;
  final String hangar;
  final String team;
  final String responsible;
  final String description;
  bool isResolved;
  final DateTime createdAt;
  DateTime? resolvedAt;

  PendingItem({
    this.id,
    this.firestoreId,
    required this.clientId,
    required this.clientName,
    this.producerName = '',
    required this.local,
    required this.hangar,
    required this.team,
    this.responsible = '',
    required this.description,
    this.isResolved = false,
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
        'is_resolved': isResolved ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'resolved_at': resolvedAt?.toIso8601String(),
      };

  factory PendingItem.fromMap(Map<String, dynamic> map) => PendingItem(
        id: map['id'] as int?,
        firestoreId: map['firestore_id'] as String?,
        clientId: map['client_id'] as String,
        clientName: map['client_name'] ?? '',
        producerName: map['producer_name'] ?? '',
        local: map['local'] ?? map['stand'] ?? '',
        hangar: map['hangar'] ?? '',
        team: map['team'] as String,
        responsible: map['responsible'] ?? '',
        description: map['description'] as String,
        isResolved: (map['is_resolved'] as int? ?? 0) == 1,
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
        local: data['local'] ?? '',
        hangar: data['hangar'] ?? '',
        team: data['team'] ?? '',
        responsible: data['responsible'] ?? '',
        description: data['description'] ?? '',
        isResolved: data['isResolved'] as bool? ?? false,
        createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ??
            DateTime.now(),
        resolvedAt: data['resolvedAt'] != null
            ? DateTime.tryParse(data['resolvedAt'] as String)
            : null,
      );

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
