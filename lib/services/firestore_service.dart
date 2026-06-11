import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pending_item.dart';
import '../models/montage_update.dart';

class FirestoreService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ─── Montage updates (fotos de andamento da montagem) ────────────────────────

  static Future<void> saveMontageUpdate({
    required String clientId,
    required String fairName,
    required String photoUrl,
    required String createdBy,
  }) async {
    // Fire-and-forget: Firestore enfileira offline e envia ao reconectar.
    _db.collection('montage_updates').add({
      'clientId': clientId,
      'fairName': fairName,
      'photoUrl': photoUrl,
      'createdBy': createdBy,
      'createdAt': DateTime.now().toIso8601String(),
    }).ignore();
  }

  static Future<List<MontageUpdate>> getMontageUpdates(String clientId) async {
    final snap = await _db
        .collection('montage_updates')
        .where('clientId', isEqualTo: clientId)
        .get();
    final list = snap.docs
        .map((d) => MontageUpdate.fromFirestore(d.id, d.data()))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Returns the set of producer names who sent at least one montage photo
  /// today (local date) for the given fair.
  static Future<Set<String>> getMontageProducersToday(String fairName) async {
    final todayPrefix =
        DateTime.now().toIso8601String().substring(0, 10); // "YYYY-MM-DD"
    try {
      final snap = await _db
          .collection('montage_updates')
          .where('fairName', isEqualTo: fairName)
          .get();
      return snap.docs
          .where((d) =>
              ((d.data()['createdAt'] as String?) ?? '').startsWith(todayPrefix))
          .map((d) => (d.data()['createdBy'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  // ─── Pending Items ───────────────────────────────────────────────────────────

  static Future<String> savePendingItem(
      PendingItem item, String fairName) async {
    final doc = _db.collection('pending_items').doc();
    // Fire-and-forget: the doc id is generated client-side, so we can return it
    // immediately. Firestore's offline cache queues the write and retries when
    // the connection returns — so creating a pending works offline in the field.
    doc.set({
      'fairName': fairName,
      'clientId': item.clientId,
      'clientName': item.clientName,
      'producerName': item.producerName,
      'local': item.local,
      'hangar': item.hangar,
      'team': item.team,
      'responsible': item.responsible,
      'description': item.description,
      'photoUrls': item.photoUrls,
      'origem': item.origem,
      'createdBy': item.createdBy,
      'resolvedBy': '',
      'approvalStatus': item.approvalStatus,
      'rejectionReason': '',
      'isResolved': false,
      'awaitingValidation': false,
      'createdAt': item.createdAt.toIso8601String(),
      'resolvedAt': null,
    }).catchError((_) {});
    return doc.id;
  }

  /// Approves an organizer request (becomes a normal pending).
  static Future<void> approveOrganizerItem(String firestoreId) async {
    if (firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'approvalStatus': 'aprovada',
    });
  }

  /// Rejects an organizer request, finalizing it with a reason.
  static Future<void> rejectOrganizerItem(String firestoreId,
      {String reason = '', String by = ''}) async {
    if (firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'approvalStatus': 'recusada',
      'rejectionReason': reason,
      'isResolved': true,
      'resolvedAt': DateTime.now().toIso8601String(),
      if (by.isNotEmpty) 'resolvedBy': by,
    });
  }

  /// All requests created by a given organizer (for the "my requests" view).
  static Future<List<PendingItem>> getOrganizerRequests(String createdBy) async {
    final snapshot = await _db
        .collection('pending_items')
        .where('createdBy', isEqualTo: createdBy)
        .get();
    final items = snapshot.docs
        .map((d) => PendingItem.fromFirestore(d.id, d.data()))
        .toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  static Future<void> resolveItem(String firestoreId,
      {String? resolvedBy}) async {
    if (firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'isResolved': true,
      'resolvedAt': DateTime.now().toIso8601String(),
      if (resolvedBy != null && resolvedBy.isNotEmpty) 'resolvedBy': resolvedBy,
    });
  }

  static Future<void> updatePendingContent(
      String firestoreId, String description, List<String> photoUrls) async {
    if (firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'description': description,
      'photoUrls': photoUrls,
    });
  }

  static Future<void> markAwaitingValidation(String firestoreId) async {
    if (firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'awaitingValidation': true,
    });
  }

  static Future<void> markInProgress(String firestoreId, String by) async {
    if (firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'inProgress': true,
      'inProgressBy': by,
    });
  }

  static Future<List<PendingItem>> getItemsByProducer(
      String producerName) async {
    final snapshot = await _db
        .collection('pending_items')
        .where('producerName', isEqualTo: producerName)
        .where('isResolved', isEqualTo: false)
        .get();
    final items = snapshot.docs
        .map((d) => PendingItem.fromFirestore(d.id, d.data()))
        .toList();
    items.sort((a, b) {
      final h = a.hangar.compareTo(b.hangar);
      if (h != 0) return h;
      return a.local.compareTo(b.local);
    });
    return items;
  }

  static Future<List<PendingItem>> getAwaitingItemsByClientId(
      String clientId) async {
    final snapshot = await _db
        .collection('pending_items')
        .where('clientId', isEqualTo: clientId)
        .get();
    return snapshot.docs
        .map((d) => PendingItem.fromFirestore(d.id, d.data()))
        .where((item) => item.awaitingValidation && !item.isResolved)
        .toList();
  }

  // ─── Producer PINs ──────────────────────────────────────────────────────────

  static Future<String?> getProducerPin(String producerName) async {
    final doc =
        await _db.collection('producer_pins').doc(producerName).get();
    if (!doc.exists) return null;
    return doc.data()?['pin'] as String?;
  }

  static Future<void> setProducerPin(String producerName, String pin) async {
    await _db
        .collection('producer_pins')
        .doc(producerName)
        .set({'pin': pin});
  }

  static Future<void> deleteProducerPin(String producerName) async {
    await _db.collection('producer_pins').doc(producerName).delete();
  }

  static Future<List<String>> getProducersWithPins() async {
    final snapshot = await _db.collection('producer_pins').get();
    final names = snapshot.docs.map((d) => d.id).toList()..sort();
    return names;
  }

  // ─── Consultant PINs ──────────────────────────────────────────────────────────

  static Future<String?> getConsultantPin(String name) async {
    final doc = await _db.collection('consultant_pins').doc(name).get();
    if (!doc.exists) return null;
    return doc.data()?['pin'] as String?;
  }

  static Future<void> setConsultantPin(String name, String pin) async {
    await _db.collection('consultant_pins').doc(name).set({'pin': pin});
  }

  static Future<void> deleteConsultantPin(String name) async {
    await _db.collection('consultant_pins').doc(name).delete();
  }

  static Future<List<String>> getConsultantsWithPins() async {
    final snapshot = await _db.collection('consultant_pins').get();
    final names = snapshot.docs.map((d) => d.id).toList()..sort();
    return names;
  }

  // ─── Organizer PINs ───────────────────────────────────────────────────────────

  static Future<String?> getOrganizerPin(String name) async {
    final doc = await _db.collection('organizer_pins').doc(name).get();
    if (!doc.exists) return null;
    return doc.data()?['pin'] as String?;
  }

  static Future<void> setOrganizerPin(String name, String pin) async {
    await _db.collection('organizer_pins').doc(name).set({'pin': pin});
  }

  static Future<void> deleteOrganizerPin(String name) async {
    await _db.collection('organizer_pins').doc(name).delete();
  }

  static Future<List<String>> getOrganizersWithPins() async {
    final snapshot = await _db.collection('organizer_pins').get();
    final names = snapshot.docs.map((d) => d.id).toList()..sort();
    return names;
  }

  // ─── Team Leader PINs ───────────────────────────────────────────────────────

  static Future<String?> getTeamLeaderPin(String name) async {
    final doc = await _db.collection('team_leader_pins').doc(name).get();
    if (!doc.exists) return null;
    return doc.data()?['pin'] as String?;
  }

  static Future<String?> getTeamLeaderTeam(String name) async {
    final doc = await _db.collection('team_leader_pins').doc(name).get();
    if (!doc.exists) return null;
    return doc.data()?['team'] as String?;
  }

  static Future<void> setTeamLeaderPin(
      String name, String pin, String team) async {
    await _db
        .collection('team_leader_pins')
        .doc(name)
        .set({'pin': pin, 'team': team});
  }

  static Future<void> deleteTeamLeaderPin(String name) async {
    await _db.collection('team_leader_pins').doc(name).delete();
  }

  /// Returns list of {name, team} maps, sorted by name.
  static Future<List<Map<String, String>>> getTeamLeadersWithPins() async {
    final snapshot = await _db.collection('team_leader_pins').get();
    final list = snapshot.docs.map((d) {
      return {
        'name': d.id,
        'team': (d.data()['team'] as String?) ?? '',
      };
    }).toList();
    list.sort((a, b) => a['name']!.compareTo(b['name']!));
    return list;
  }

  // ─── Fairs ──────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getFairs() async {
    final snapshot = await _db.collection('fairs').get();
    return snapshot.docs
        .map((d) => {'id': int.tryParse(d.id), ...d.data()})
        .toList();
  }

  static Future<void> saveFair(int id, String name, String spreadsheetId,
      String sheetName, String createdAt, {String mode = 'producao'}) async {
    await _db.collection('fairs').doc(id.toString()).set({
      'name': name,
      'spreadsheetId': spreadsheetId,
      'sheetName': sheetName,
      'createdAt': createdAt,
      'mode': mode,
    });
  }

  /// Reads a single fair document (used by the public stand web page).
  static Future<Map<String, dynamic>?> getFair(int id) async {
    final doc = await _db.collection('fairs').doc(id.toString()).get();
    if (!doc.exists) return null;
    return {'id': id, ...doc.data()!};
  }

  /// Updates only the operating mode of a fair (producao / manutencao).
  static Future<void> setFairMode(int id, String mode) async {
    await _db.collection('fairs').doc(id.toString()).set(
      {'mode': mode},
      SetOptions(merge: true),
    );
  }

  static Future<void> deleteFairFromCloud(int id) async {
    try {
      await _db.collection('fairs').doc(id.toString()).delete();
    } catch (_) {}
  }

  /// Real-time stream of all pending items for a given fair name.
  static Stream<List<PendingItem>> streamPendingByFair(String fairName) {
    return _db
        .collection('pending_items')
        .where('fairName', isEqualTo: fairName)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => PendingItem.fromFirestore(d.id, d.data()))
            .toList());
  }

  // ─── Team ────────────────────────────────────────────────────────────────────

  static Future<List<PendingItem>> getPendingItemsByTeam(
      String team) async {
    final snapshot = await _db
        .collection('pending_items')
        .where('team', isEqualTo: team)
        .where('isResolved', isEqualTo: false)
        .get();
    final items = snapshot.docs
        .map((d) => PendingItem.fromFirestore(d.id, d.data()))
        .toList();
    items.sort((a, b) {
      final h = a.hangar.compareTo(b.hangar);
      if (h != 0) return h;
      return a.local.compareTo(b.local);
    });
    return items;
  }
}
