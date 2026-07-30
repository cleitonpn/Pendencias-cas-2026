import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// Upload de fotos para o Firebase Storage.
///
/// Trabalha com [XFile] e bytes em vez de `dart:io File`: é o que permite o
/// mesmo código rodar no Android e no navegador. No web não existe caminho de
/// arquivo — o `putFile` simplesmente não compila lá.
class StorageService {
  static final _storage = FirebaseStorage.instance;

  static Future<String> _upload(String path, XFile file) async {
    final bytes = await file.readAsBytes();
    final task = await _storage.ref(path).putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
    return task.ref.getDownloadURL();
  }

  /// Envia uma foto de pendência e devolve a URL pública.
  /// Caminho: pending_photos/<fairId>/<timestamp>_<index>.jpg
  static Future<String> uploadPendingPhoto({
    required int fairId,
    required XFile file,
    required int index,
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return _upload('pending_photos/$fairId/${ts}_$index.jpg', file);
  }

  /// Envia várias fotos e devolve as URLs, na ordem.
  static Future<List<String>> uploadPendingPhotos({
    required int fairId,
    required List<XFile> files,
  }) async {
    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      urls.add(await uploadPendingPhoto(fairId: fairId, file: files[i], index: i));
    }
    return urls;
  }

  /// Comprovante de um pedido de frete.
  /// Caminho: freight_receipts/<requestId>.jpg
  static Future<String> uploadReceiptPhoto({
    required String requestId,
    required XFile file,
  }) =>
      _upload('freight_receipts/$requestId.jpg', file);
}
