import 'package:ota_update/ota_update.dart';
import 'apk_progress.dart';

/// Native: downloads the APK and triggers the system installer. The OS shows
/// the install screen automatically once the download finishes (the user must
/// have allowed "install unknown apps" for this app once).
Stream<ApkProgress> installApk(String url) {
  return OtaUpdate()
      .execute(url, destinationFilename: 'montagem-uset-update.apk')
      .map((e) => ApkProgress(
            status: e.status.name,
            percent: int.tryParse(e.value ?? '') ?? -1,
          ));
}
