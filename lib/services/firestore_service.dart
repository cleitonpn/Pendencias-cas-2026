import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pending_item.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  // ─── Pending Items ───────────────────────────────────────────────────────────

  static Future<String> savePendingItem(
      PendingItem item, String fairName) async {
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
      'createdAt': item.createdAt.toIso8601String(),
      'resolvedAt': null,
    });
    return doc.id;
  }

  static Future<void> resolveItem(String firestoreId) async {
    await _db.collection('pending_items').doc(firestoreId).update({
      'isResolved': true,
      'resolvedAt': DateTime.now().toIso8601String(),
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
}
