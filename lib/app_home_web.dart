import 'package:flutter/material.dart';
import 'screens/stand_request_screen.dart';

/// Web: the app is the public exhibitor page. The QR code uses the hash
/// strategy (…/#/stand?f=<fair>&c=<rowId>), so params may live in the URL
/// fragment or the query string — read both.
Widget buildHome() {
  final base = Uri.base;
  final qp = <String, String>{...base.queryParameters};
  if (base.fragment.isNotEmpty) {
    final frag =
        base.fragment.startsWith('/') ? base.fragment : '/${base.fragment}';
    final fragUri = Uri.tryParse(frag);
    if (fragUri != null) qp.addAll(fragUri.queryParameters);
  }
  return StandRequestScreen(
    fairId: int.tryParse(qp['f'] ?? ''),
    rowId: (qp['c'] ?? '').isEmpty ? null : qp['c'],
  );
}
