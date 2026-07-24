import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pending_item.dart';
import '../models/montage_update.dart';
import '../models/freight_request.dart';

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

  /// Real-time stream of all organizer items awaiting consultant approval,
  /// across every fair. Filters in memory to avoid composite index requirement.
  static Stream<List<PendingItem>> streamAllPendingApprovals() {
    return _db
        .collection('pending_items')
        .where('origem', isEqualTo: 'organizadora')
        .snapshots()
        .map((snap) {
      final items = snap.docs
          .map((d) => PendingItem.fromFirestore(d.id, d.data()))
          .where((item) => item.approvalStatus == 'pendente' && !item.isResolved)
          .toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
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
    await _db
        .collection('organizer_pins')
        .doc(name)
        .set({'pin': pin}, SetOptions(merge: true));
  }

  static Future<void> deleteOrganizerPin(String name) async {
    await _db.collection('organizer_pins').doc(name).delete();
  }

  /// Returns the fair ID linked to this organizer, or null if not set.
  static Future<int?> getOrganizerFairId(String name) async {
    final doc = await _db.collection('organizer_pins').doc(name).get();
    if (!doc.exists) return null;
    final v = doc.data()?['fairId'];
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Associates an organizer with a specific fair (merges into existing doc).
  static Future<void> setOrganizerFairId(String name, int fairId) async {
    await _db
        .collection('organizer_pins')
        .doc(name)
        .set({'fairId': fairId}, SetOptions(merge: true));
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

  /// Real-time stream of all fairs — used to sync mode changes across devices.
  static Stream<List<Map<String, dynamic>>> streamFairs() {
    return _db.collection('fairs').snapshots().map(
      (snap) => snap.docs
          .map((d) => {'id': int.tryParse(d.id), ...d.data()})
          .toList(),
    );
  }

  /// Updates derived (mestra_child) fair metadata WITHOUT touching the mode field,
  /// so that mode changes made via setFairMode() are preserved across syncs.
  static Future<void> saveDerivedFairMetadata(int id, String name,
      String spreadsheetId, String sheetName, String createdAt) async {
    try {
      await _db.collection('fairs').doc(id.toString()).set({
        'id': id,
        'name': name,
        'spreadsheetId': spreadsheetId,
        'sheetName': sheetName,
        'createdAt': createdAt,
        'sheetMode': 'mestra_child',
        // mode field intentionally omitted — preserved by setFairMode()
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> saveFair(int id, String name, String spreadsheetId,
      String sheetName, String createdAt,
      {String mode = 'producao', String sheetMode = 'individual'}) async {
    await _db.collection('fairs').doc(id.toString()).set({
      'name': name,
      'spreadsheetId': spreadsheetId,
      'sheetName': sheetName,
      'createdAt': createdAt,
      'mode': mode,
      'sheetMode': sheetMode,
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

  static Future<void> archiveFairInCloud(int id, bool archived) async {
    try {
      final snap = await _db.collection('fairs').where('id', isEqualTo: id).limit(1).get();
      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.update({'archived': archived});
      } else {
        // Also try by doc id directly
        await _db.collection('fairs').doc(id.toString()).set({'archived': archived}, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  // ─── Client Specs ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getClientSpecs(String clientId) async {
    try {
      final doc = await _db.collection('client_specs').doc(clientId).get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  // ─── Sync Events (new-client notifications) ──────────────────────────────────

  /// Writes a transient event document that triggers the `onNewClientSynced`
  /// Cloud Function, which sends FCM notifications to producer + consultant.
  static void writeSyncEvent({
    required String clientId,
    required String clientName,
    required String fairName,
    required String producerName,
    required String consultantName,
  }) {
    if (producerName.isEmpty && consultantName.isEmpty) return;
    _db.collection('sync_events').add({
      'clientId': clientId,
      'clientName': clientName,
      'fairName': fairName,
      'producerName': producerName,
      'consultantName': consultantName,
      'createdAt': DateTime.now().toIso8601String(),
    }).catchError((_) {});
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

  // ─── Manager PINs ────────────────────────────────────────────────────────────

  static Future<String?> getManagerPin(String name) async {
    final doc = await _db.collection('manager_pins').doc(name).get();
    if (!doc.exists) return null;
    return doc.data()?['pin'] as String?;
  }

  static Future<void> setManagerPin(String name, String pin) async {
    await _db.collection('manager_pins').doc(name).set({'pin': pin});
  }

  static Future<void> deleteManagerPin(String name) async {
    await _db.collection('manager_pins').doc(name).delete();
  }

  static Future<List<String>> getManagersWithPins() async {
    final snapshot = await _db.collection('manager_pins').get();
    final names = snapshot.docs.map((d) => d.id).toList()..sort();
    return names;
  }

  // ─── Analyst PINs ────────────────────────────────────────────────────────────

  static Future<String?> getAnalystPin(String name) async {
    final doc = await _db.collection('analyst_pins').doc(name).get();
    if (!doc.exists) return null;
    return doc.data()?['pin'] as String?;
  }

  static Future<void> setAnalystPin(String name, String pin) async {
    await _db.collection('analyst_pins').doc(name).set({'pin': pin});
  }

  static Future<void> deleteAnalystPin(String name) async {
    await _db.collection('analyst_pins').doc(name).delete();
  }

  static Future<List<String>> getAnalystsWithPins() async {
    final snapshot = await _db.collection('analyst_pins').get();
    final names = snapshot.docs.map((d) => d.id).toList()..sort();
    return names;
  }

  // ─── Spec Locking ─────────────────────────────────────────────────────────

  static Future<void> saveClientSpecs(
      String clientId, Map<String, dynamic> specs) async {
    await _db
        .collection('client_specs')
        .doc(clientId)
        .set(specs, SetOptions(merge: true));
  }

  static Future<void> lockClientSpecs(String clientId) async {
    await _db.collection('client_specs').doc(clientId).set(
      {'locked': true, 'lockedAt': DateTime.now().toIso8601String()},
      SetOptions(merge: true),
    );
  }

  static Future<void> unlockClientSpecs(String clientId) async {
    await _db.collection('client_specs').doc(clientId).set(
      {'locked': false, 'editRequested': false},
      SetOptions(merge: true),
    );
  }

  /// Consultant requests permission to edit — sets editRequested flag and
  /// writes a spec_edit_requests doc so admins get notified via CF.
  static Future<void> requestSpecEdit(String clientId, String clientName,
      String fairName, String byName) async {
    await _db.collection('client_specs').doc(clientId).set(
      {'editRequested': true},
      SetOptions(merge: true),
    );
    _db.collection('spec_edit_requests').doc(clientId).set({
      'clientId': clientId,
      'clientName': clientName,
      'fairName': fairName,
      'requestedBy': byName,
      'requestedAt': DateTime.now().toIso8601String(),
    }).catchError((_) {});
  }

  static Future<List<Map<String, dynamic>>> getPendingSpecEditRequests() async {
    try {
      final snap = await _db.collection('spec_edit_requests').get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> approveSpecEditRequest(String clientId) async {
    await unlockClientSpecs(clientId);
    try {
      await _db.collection('spec_edit_requests').doc(clientId).delete();
    } catch (_) {}
  }

  /// Writes a spec_change_events doc → Cloud Function sends to `admins` topic.
  static void writeSpecChangeEvent({
    required String clientId,
    required String clientName,
    required String fairName,
    required String consultantName,
  }) {
    _db.collection('spec_change_events').add({
      'clientId': clientId,
      'clientName': clientName,
      'fairName': fairName,
      'consultantName': consultantName,
      'notifyTopic': 'admins',
      'createdAt': DateTime.now().toIso8601String(),
    }).catchError((_) {});
  }

  // ─── Analyst Notes ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getAnalystNote(String clientId) async {
    try {
      final doc = await _db.collection('analyst_notes').doc(clientId).get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveAnalystNote(
      String clientId, String text, String link, String by) async {
    await _db.collection('analyst_notes').doc(clientId).set({
      'text': text,
      'link': link,
      'updatedBy': by,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  // ─── New Client Broadcast ─────────────────────────────────────────────────

  /// Writes to new_client_broadcasts → CF sends to `new_clients` FCM topic.
  /// Uses clientId as the stable document ID so the CF onCreate trigger only
  /// fires once per client, preventing duplicate notifications on every sync.
  static void writeNewClientBroadcast({
    required String clientId,
    required String clientName,
    required String fairName,
  }) {
    _db.collection('new_client_broadcasts').doc(clientId).set({
      'clientId': clientId,
      'clientName': clientName,
      'fairName': fairName,
      'notifyTopic': 'new_clients',
      'createdAt': DateTime.now().toIso8601String(),
    }).catchError((_) {});
  }

  // ─── Admin Users ──────────────────────────────────────────────────────────

  static Future<List<String>> getAdminUsers() async {
    try {
      final snap = await _db.collection('admin_users').orderBy('name').get();
      return snap.docs.map((d) => (d.data()['name'] as String?) ?? '').where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String?> getAdminUserPin(String name) async {
    try {
      final snap = await _db.collection('admin_users').where('name', isEqualTo: name).limit(1).get();
      if (snap.docs.isEmpty) return null;
      return snap.docs.first.data()['pin'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveAdminUser(String name, String pin) async {
    final key = name.toLowerCase().trim().replaceAll(' ', '_').replaceAll(RegExp(r'[^a-z0-9_]'), '');
    await _db.collection('admin_users').doc(key).set({'name': name, 'pin': pin});
  }

  static Future<void> deleteAdminUser(String name) async {
    final key = name.toLowerCase().trim().replaceAll(' ', '_').replaceAll(RegExp(r'[^a-z0-9_]'), '');
    await _db.collection('admin_users').doc(key).delete();
  }

  // ─── Avisos ───────────────────────────────────────────────────────────────

  static Future<void> writeAviso({
    required String title,
    required String body,
    required String createdBy,
    required List<String> targetGroups,
    String targetType = 'groups',
    List<Map<String, dynamic>> targetUsers = const [],
  }) async {
    await _db.collection('avisos').add({
      'title': title,
      'body': body,
      'createdBy': createdBy,
      'targetGroups': targetGroups,
      'targetType': targetType,
      'targetUsers': targetUsers,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> deleteAviso(String docId) async {
    await _db.collection('avisos').doc(docId).delete();
  }

  static Stream<List<Map<String, dynamic>>> streamAvisos() {
    return _db
        .collection('avisos')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList());
  }

  // ─── Presence ─────────────────────────────────────────────────────────────

  static Future<void> updatePresence({
    required String name,
    required String role,
    required String team,
    required bool online,
  }) async {
    if (name.isEmpty && role.isEmpty) return;
    final key = '${role}_$name'
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
    try {
      await _db.collection('presence').doc(key).set({
        'name': name,
        'role': role,
        'team': team,
        'online': online,
        'lastSeen': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  static Future<void> clearPresence(String name, String role) async {
    await updatePresence(name: name, role: role, team: '', online: false);
  }

  static Stream<List<Map<String, dynamic>>> streamPresence() {
    return _db
        .collection('presence')
        .orderBy('lastSeen', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList());
  }

  // ─── Gallery ──────────────────────────────────────────────────────────────

  /// Returns all montage photos for [fairName] on [date] (e.g. "2026-06-15").
  static Future<List<Map<String, dynamic>>> getMontagePhotosByDate(
      String fairName, String date) async {
    try {
      final snap = await _db
          .collection('montage_updates')
          .where('fairName', isEqualTo: fairName)
          .get();
      return snap.docs
          .map((d) => d.data())
          .where((d) =>
              ((d['createdAt'] as String?) ?? '').startsWith(date))
          .toList();
    } catch (_) {
      return [];
    }
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

  // ─── Logistics Users ──────────────────────────────────────────────────────

  static Future<List<String>> getLogisticsUsers() async {
    try {
      final snap = await _db.collection('logistics_users').orderBy('name').get();
      return snap.docs
          .map((d) => (d.data()['name'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String?> getLogisticsUserPin(String name) async {
    try {
      final key = name.toLowerCase().trim()
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'[^a-z0-9_]'), '');
      final doc = await _db.collection('logistics_users').doc(key).get();
      if (!doc.exists) return null;
      return doc.data()?['pin'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveLogisticsUser(String name, String pin) async {
    final key = name.toLowerCase().trim()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
    await _db.collection('logistics_users').doc(key).set({'name': name, 'pin': pin});
  }

  static Future<void> deleteLogisticsUser(String name) async {
    final key = name.toLowerCase().trim()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
    await _db.collection('logistics_users').doc(key).delete();
  }

  // ─── Freight Requests ─────────────────────────────────────────────────────

  static Future<void> createFreightRequest(FreightRequest req) async {
    final snap = await _db
        .collection('freight_requests')
        .where('fairId', isEqualTo: req.fairId)
        .get();
    final number = snap.docs.length + 1;
    await _db.collection('freight_requests').add({...req.toMap(), 'number': number});
  }

  static Stream<List<FreightRequest>> streamFreightRequests(int fairId) {
    Query q = _db.collection('freight_requests');
    if (fairId >= 0) q = q.where('fairId', isEqualTo: fairId);
    return q
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => FreightRequest.fromMap(d.id, d.data() as Map<String, dynamic>))
            .toList());
  }

  static Future<void> updateFreightRequestStatus(
      String id, String status, String handledBy,
      {String note = '', String photoUrl = ''}) async {
    final now = DateTime.now().toIso8601String();
    final update = <String, dynamic>{'status': status, 'handledBy': handledBy};
    if (note.isNotEmpty) update['statusNote'] = note;
    if (status == 'agendado') update['scheduledAt'] = now;
    if (status == 'despachado') update['dispatchedAt'] = now;
    if (status == 'finalizado') {
      update['finalizedAt'] = now;
      if (photoUrl.isNotEmpty) update['receiptPhotoUrl'] = photoUrl;
    }
    await _db.collection('freight_requests').doc(id).update(update);
  }

  static Future<void> deleteFreightRequest(String id) async {
    await _db.collection('freight_requests').doc(id).delete();
  }

  static Future<List<FreightRequest>> getFreightRequestsForReport(int fairId) async {
    final snap = await _db
        .collection('freight_requests')
        .where('fairId', isEqualTo: fairId)
        .where('status', isEqualTo: 'finalizado')
        .get();
    return snap.docs
        .map((d) => FreightRequest.fromMap(d.id, d.data() as Map<String, dynamic>))
        .toList();
  }
}
