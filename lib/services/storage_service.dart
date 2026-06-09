import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  static final _storage = FirebaseStorage.instance;

  /// Uploads a local image file to Firebase Storage and returns its public
  /// download URL. Path: pending_photos/<fairId>/<timestamp>_<index>.jpg
  static Future<String> uploadPendingPhoto({
    required int fairId,
    required File file,
    required int index,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref('pending_photos/$fairId/${ts}_$index.jpg');
    final task = await ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return task.ref.getDownloadURL();
  }

  /// Uploads several photos and returns their download URLs (in order).
  static Future<List<String>> uploadPendingPhotos({
    required int fairId,
    required List<File> files,
  }) async {
    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      urls.add(await uploadPendingPhoto(fairId: fairId, file: files[i], index: i));
    }
    return urls;
  }
}
