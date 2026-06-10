import 'package:flutter/material.dart';
import 'screens/stand_request_screen.dart';
import 'screens/organizer_web_screen.dart';

/// Web: the app is a public page. Two routes share the same Flutter Web build,
/// selected by the URL fragment (hash strategy works on static hosting):
///   …/#/stand?f=<fair>&c=<rowId>   → exhibitor maintenance request (QR)
///   …/#/organizadora?f=<fair>      → event organizer request portal
Widget buildHome() {
  final base = Uri.base;
  final qp = <String, String>{...base.queryParameters};
  String path = '';
  if (base.fragment.isNotEmpty) {
    final frag =
        base.fragment.startsWith('/') ? base.fragment : '/${base.fragment}';
    final fragUri = Uri.tryParse(frag);
    if (fragUri != null) {
      qp.addAll(fragUri.queryParameters);
      path = fragUri.path;
    }
  }

  final fairId = int.tryParse(qp['f'] ?? '');

  if (path.contains('organizadora')) {
    return OrganizerWebScreen(fairId: fairId);
  }

  return StandRequestScreen(
    fairId: fairId,
    rowId: (qp['c'] ?? '').isEmpty ? null : qp['c'],
  );
}
