class PendingItem {
  final int? id;
  final String clientId;
  final String clientName;
  final String stand;
  final String hangar;
  final String team;
  final String description;
  bool isResolved;
  final DateTime createdAt;
  DateTime? resolvedAt;

  PendingItem({
    this.id,
    required this.clientId,
    required this.clientName,
    required this.stand,
    required this.hangar,
    required this.team,
    required this.description,
    this.isResolved = false,
    required this.createdAt,
    this.resolvedAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'client_id': clientId,
        'client_name': clientName,
        'stand': stand,
        'hangar': hangar,
        'team': team,
        'description': description,
        'is_resolved': isResolved ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'resolved_at': resolvedAt?.toIso8601String(),
      };

  factory PendingItem.fromMap(Map<String, dynamic> map) => PendingItem(
        id: map['id'] as int?,
        clientId: map['client_id'] as String,
        clientName: map['client_name'] ?? '',
        stand: map['stand'] ?? '',
        hangar: map['hangar'] ?? '',
        team: map['team'] as String,
        description: map['description'] as String,
        isResolved: (map['is_resolved'] as int? ?? 0) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        resolvedAt: map['resolved_at'] != null
            ? DateTime.tryParse(map['resolved_at'] as String)
            : null,
      );

  String toWhatsAppText() {
    final d = createdAt;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '*PENDÊNCIA - CAS 2026*\n'
        'Hangar: $hangar | Stand: $stand\n'
        'Cliente: $clientName\n'
        'Equipe: $team\n'
        'Pendência: $description\n'
        'Registrado: $dateStr';
  }
}
