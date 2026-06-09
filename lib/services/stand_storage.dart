import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

/// Web-safe photo upload for the public stand page (no dart:io).
/// image_picker returns bytes, which we upload directly to Firebase Storage.
class StandStorage {
  static final _storage = FirebaseStorage.instance;

  static Future<String> uploadPhotoBytes({
    required int fairId,
    required Uint8List bytes,
    required int index,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref('pending_photos/$fairId/stand_${ts}_$index.jpg');
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return task.ref.getDownloadURL();
  }
}
