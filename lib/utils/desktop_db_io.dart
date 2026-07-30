import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Driver FFI do SQLite no Windows/Linux/macOS.
/// No Android/iOS o driver padrão do sqflite é usado — aqui vira no-op.
void initDesktopDatabase() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
