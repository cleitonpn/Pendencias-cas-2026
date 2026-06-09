import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/pending_item.dart';

class FirestoreService {
  // Firestore is only available on mobile/web — not on Windows/Linux/macOS
  // desktop builds (which skip Firebase initialization).
  static bool get _available {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS;
  }

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ─── Pending Items ───────────────────────────────────────────────────────────

  static Future<String> savePendingItem(
      PendingItem item, String fairName) async {
    if (!_available) return '';
    final doc = _db.collection('pending_items').doc();
    await doc.set({
      'fairName': fairName,
      'clientId': item.clientId,
      'clientName': item.clientName,
      'producerName': item.producerName,
      'local': item.local,
      'hangar': item.hangar,
      'team': item.team,
      'responsible': item.responsible,
      'description': item.description,
      'isResolved': false,
      'awaitingValidation': false,
      'createdAt': item.createdAt.toIso8601String(),
      'resolvedAt': null,
    });
    return doc.id;
  }

  static Future<void> resolveItem(String firestoreId) async {
    if (!_available || firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'isResolved': true,
      'resolvedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> markAwaitingValidation(String firestoreId) async {
    if (!_available || firestoreId.isEmpty) return;
    await _db.collection('pending_items').doc(firestoreId).update({
      'awaitingValidation': true,
    });
  }

  static Future<List<PendingItem>> getItemsByProducer(
      String producerName) async {
    if (!_available) return [];
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
    if (!_available) return [];
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
    if (!_available) return null;
    final doc =
        await _db.collection('producer_pins').doc(producerName).get();
    if (!doc.exists) return null;
    return doc.data()?['pin'] as String?;
  }

  static Future<void> setProducerPin(String producerName, String pin) async {
    if (!_available) return;
    await _db
        .collection('producer_pins')
        .doc(producerName)
        .set({'pin': pin});
  }

  static Future<void> deleteProducerPin(String producerName) async {
    if (!_available) return;
    await _db.collection('producer_pins').doc(producerName).delete();
  }

  static Future<List<String>> getProducersWithPins() async {
    if (!_available) return [];
    final snapshot = await _db.collection('producer_pins').get();
    final names = snapshot.docs.map((d) => d.id).toList()..sort();
    return names;
  }

  // ─── Team Leader PINs ───────────────────────────────────────────────────────

  static Future<String?> getTeamLeaderPin(String name) async {
    if (!_available) return null;
    final doc = await _db.collection('team_leader_pins').doc(name).get();
    if (!doc.exists) return null;
    return doc.data()?['pin'] as String?;
  }

  static Future<String?> getTeamLeaderTeam(String name) async {
    if (!_available) return null;
    final doc = await _db.collection('team_leader_pins').doc(name).get();
    if (!doc.exists) return null;
    return doc.data()?['team'] as String?;
  }

  static Future<void> setTeamLeaderPin(
      String name, String pin, String team) async {
    if (!_available) return;
    await _db
        .collection('team_leader_pins')
        .doc(name)
        .set({'pin': pin, 'team': team});
  }

  static Future<void> deleteTeamLeaderPin(String name) async {
    if (!_available) return;
    await _db.collection('team_leader_pins').doc(name).delete();
  }

  /// Returns list of {name, team} maps, sorted by name.
  static Future<List<Map<String, String>>> getTeamLeadersWithPins() async {
    if (!_available) return [];
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
    if (!_available) return [];
    final snapshot = await _db.collection('fairs').get();
    return snapshot.docs.map((d) => {'id': int.tryParse(d.id), ...d.data()}).toList();
  }

  static Future<void> saveFair(int id, String name, String spreadsheetId,
      String sheetName, String createdAt) async {
    if (!_available) return;
    await _db.collection('fairs').doc(id.toString()).set({
      'name': name,
      'spreadsheetId': spreadsheetId,
      'sheetName': sheetName,
      'createdAt': createdAt,
    });
  }

  static Future<void> deleteFairFromCloud(int id) async {
    if (!_available) return;
    try {
      await _db.collection('fairs').doc(id.toString()).delete();
    } catch (_) {}
  }

  // ────────────────────────────────────────────────────────────────────────────

  static Future<List<PendingItem>> getPendingItemsByTeam(
      String team) async {
    if (!_available) return [];
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
