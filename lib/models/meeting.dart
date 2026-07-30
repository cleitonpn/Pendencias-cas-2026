import '../services/directory_service.dart';

/// Uma reunião agendada no app.
///
/// Sempre vinculada a uma feira: é a feira que dá contexto a quem recebe o
/// convite e é por ela que a lista é filtrada.
class Meeting {
  final String id;
  final String title;
  final int fairId;
  final String fairName;
  final String location;
  final DateTime startsAt;
  final String createdBy;
  final DateTime createdAt;
  final List<AppUser> participants;
  final bool canceled;
  final String notes;

  const Meeting({
    required this.id,
    required this.title,
    required this.fairId,
    required this.fairName,
    required this.location,
    required this.startsAt,
    required this.createdBy,
    required this.createdAt,
    required this.participants,
    this.canceled = false,
    this.notes = '',
  });

  bool get isPast => startsAt.isBefore(DateTime.now());

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'fairId': fairId,
        'fairName': fairName,
        'location': location,
        // ISO em UTC: a função de lembrete compara texto com texto, e um
        // fuso escrito de outro jeito quebraria a comparação.
        'startsAt': startsAt.toUtc().toIso8601String(),
        'createdBy': createdBy,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'participants': participants.map((p) => p.toMap()).toList(),
        'canceled': canceled,
        'notes': notes,
      };

  factory Meeting.fromFirestore(String id, Map<String, dynamic> m) {
    final raw = (m['participants'] as List?) ?? const [];
    return Meeting(
      id: id,
      title: (m['title'] as String?) ?? '',
      fairId: (m['fairId'] as num?)?.toInt() ?? 0,
      fairName: (m['fairName'] as String?) ?? '',
      location: (m['location'] as String?) ?? '',
      startsAt:
          DateTime.tryParse((m['startsAt'] as String?) ?? '')?.toLocal() ??
              DateTime.now(),
      createdBy: (m['createdBy'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((m['createdAt'] as String?) ?? '')?.toLocal() ??
              DateTime.now(),
      participants: raw.map((e) {
        final p = Map<String, dynamic>.from(e as Map);
        return AppUser(
          name: (p['name'] as String?) ?? '',
          role: (p['role'] as String?) ?? '',
          team: (p['team'] as String?) ?? '',
        );
      }).where((p) => p.name.isNotEmpty).toList(),
      canceled: m['canceled'] == true,
      notes: (m['notes'] as String?) ?? '',
    );
  }

  /// Verdadeiro se esta pessoa foi convidada.
  bool includes(String name, String role) => participants.any((p) =>
      p.role == role &&
      p.name.toLowerCase().trim() == name.toLowerCase().trim());
}
