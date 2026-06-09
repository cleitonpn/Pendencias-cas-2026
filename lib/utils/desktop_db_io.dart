import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Initializes the FFI SQLite driver on Windows/Linux/macOS.
/// On Android/iOS the default sqflite driver is used, so this is a no-op.
void initDesktopDatabase() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
