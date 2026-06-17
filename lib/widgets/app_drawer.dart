import 'package:flutter/material.dart';
import '../screens/cronograma_screen.dart';
import '../screens/gallery_screen.dart';
import '../screens/circular_list_screen.dart';
import '../screens/presence_screen.dart';

class AppDrawer extends StatelessWidget {
  final bool showGallery;
  const AppDrawer({super.key, this.showGallery = false});

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
          if (showGallery)
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
            title: const Text('⚠️ Avisos',
                style: TextStyle(fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => const CircularListScreen()));
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
