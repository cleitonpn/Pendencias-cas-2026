import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/stand_request_screen.dart';
import 'screens/organizer_web_screen.dart';
import 'screens/team_web_screen.dart';

/// Web: the app is a public page. Two routes share the same Flutter Web build,
/// selected by the URL fragment (hash strategy works on static hosting):
///   …/#/stand?f=<fair>&c=<rowId>   → exhibitor maintenance request (QR)
///   …/#/organizadora?f=<fair>      → event organizer request portal
///   …/#/equipe?f=<fair>            → consultant / team leader portal (iOS)
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
  final rowId = (qp['c'] ?? '').isEmpty ? null : qp['c'];

  if (path.contains('organizadora')) {
    return OrganizerWebScreen(fairId: fairId);
  }

  // Portal de consultor e líder — para quem usa iPhone e não tem o app.
  if (path.contains('equipe')) {
    return TeamWebScreen(fairId: fairId);
  }

  // URL does not identify this as an organizer link, but a saved session may
  // exist (e.g. after the organizer refreshed to the bare root URL). Check
  // SharedPreferences asynchronously before committing to a screen.
  return _WebRouter(fairId: fairId, rowId: rowId);
}

class _WebRouter extends StatefulWidget {
  final int? fairId;
  final String? rowId;
  const _WebRouter({this.fairId, this.rowId});

  @override
  State<_WebRouter> createState() => _WebRouterState();
}

class _WebRouterState extends State<_WebRouter> {
  bool _ready = false;
  bool _isOrganizer = false;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('org_verified_name');
    if (mounted) {
      setState(() {
        _isOrganizer = name != null && name.isNotEmpty;
        _ready = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Color(0xFFF0F2F5),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_isOrganizer) {
      return OrganizerWebScreen(fairId: widget.fairId);
    }
    return StandRequestScreen(fairId: widget.fairId, rowId: widget.rowId);
  }
}
