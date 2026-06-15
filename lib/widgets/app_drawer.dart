import 'package:flutter/material.dart';
import '../screens/cronograma_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

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
        ],
      ),
    );
  }
}
