/// Conditional home widget. On web the app IS the public stand page; on
/// native platforms it's the full admin/team app starting at the splash.
/// Using a conditional import keeps the dart:io-based admin tree out of the
/// web compilation graph (it would otherwise fail to compile).
export 'app_home_web.dart' if (dart.library.io) 'app_home_io.dart';
