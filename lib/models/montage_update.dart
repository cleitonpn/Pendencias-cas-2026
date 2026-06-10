/// A montage progress photo sent by the producer for a specific stand/client.
/// Stored in Firestore (collection "montage_updates") and shown on the client
/// card as a timeline of how the stand evolved.
class MontageUpdate {
  final String id;        // Firestore document id
  final String clientId;
  final String fairName;
  final String photoUrl;
  final String createdBy; // who sent it (producer name)
  final DateTime createdAt;

  MontageUpdate({
    required this.id,
    required this.clientId,
    required this.fairName,
    required this.photoUrl,
    required this.createdBy,
    required this.createdAt,
  });

  factory MontageUpdate.fromFirestore(String id, Map<String, dynamic> data) =>
      MontageUpdate(
        id: id,
        clientId: (data['clientId'] as String?) ?? '',
        fairName: (data['fairName'] as String?) ?? '',
        photoUrl: (data['photoUrl'] as String?) ?? '',
        createdBy: (data['createdBy'] as String?) ?? '',
        createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
