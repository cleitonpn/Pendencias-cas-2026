/// Conditional entry point for desktop SQLite (FFI) initialization.
/// On web, the stub is used (no dart:io / dart:ffi), keeping the web build
/// compilable; on native platforms the real implementation runs.
export 'desktop_db_stub.dart'
    if (dart.library.io) 'desktop_db_io.dart';
