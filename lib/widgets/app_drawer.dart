import 'package:flutter/material.dart';
import '../screens/cronograma_screen.dart';
import '../screens/gallery_screen.dart';
import '../screens/circular_list_screen.dart';
import '../screens/meeting_list_screen.dart';
import '../screens/presence_screen.dart';
import '../services/session_service.dart';
import '../screens/freight_requests_screen.dart';

class AppDrawer extends StatefulWidget {
  final bool showGallery;
  const AppDrawer({super.key, this.showGallery = false});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String _role = '';
  String _name = '';

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final s = await SessionService.get();
    if (mounted && s != null) {
      setState(() {
        _role = s['role'] ?? '';
        _name = s['name'] ?? '';
      });
    }
  }

  bool get _showFreight =>
      _role == 'admin' ||
      _role == 'manager' ||
      _role == 'logistica' ||
      _role == 'producer' ||
      _role == 'consultant';

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF1E3A5F)),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.construction, color: Colors.white70, size: 32),
                  SizedBox(height: 8),
                  Text('Montagem USET',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined,
                color: Color(0xFF1E3A5F)),
            title: const Text('Cronograma',
                style: TextStyle(fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CronogramaScreen()));
            },
          ),
          if (widget.showGallery)
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: Color(0xFF1E3A5F)),
              title: const Text('Galeria',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const GalleryScreen()));
              },
            ),
          ListTile(
            leading: const Icon(Icons.campaign_outlined,
                color: Color(0xFF1E3A5F)),
            title: const Text('Avisos',
                style: TextStyle(fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => const CircularListScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.event_note_outlined,
                color: Color(0xFF1E3A5F)),
            title: const Text('Agenda de Reuniões',
                style: TextStyle(fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => const MeetingListScreen()));
            },
          ),
          if (_showFreight)
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined,
                  color: Color(0xFF1E3A5F)),
              title: const Text('Solicitações de Frete',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FreightRequestsScreen(
                      fairId: -1,
                      fairName: 'Todas as Feiras',
                      viewerRole: _role,
                      viewerName: _name,
                    ),
                  ),
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.people_outline, color: Color(0xFF1E3A5F)),
            title: const Text('Usuários Online',
                style: TextStyle(fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PresenceScreen()));
            },
          ),
        ],
      ),
    );
  }
}
