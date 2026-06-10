/// Conditional installer. Uses the ota_update plugin on native platforms and a
/// no-op stub on web, keeping the (Android-only) plugin out of the web build.
export 'apk_installer_stub.dart' if (dart.library.io) 'apk_installer_io.dart';
