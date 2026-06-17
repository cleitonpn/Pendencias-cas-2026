import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class PresenceScreen extends StatelessWidget {
  const PresenceScreen({super.key});

  static const _navy = Color(0xFF1E3A5F);

  String _roleLabel(String role) {
    switch (role) {
      case 'admin': return 'Admin';
      case 'manager': return 'Gerente';
      case 'producer': return 'Produtor';
      case 'consultant': return 'Consultor';
      case 'leader': return 'Líder';
      case 'analyst': return 'Analista';
      default: return role;
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin': return const Color(0xFF7C3AED);
      case 'manager': return const Color(0xFF1D4ED8);
      case 'producer': return const Color(0xFF065F46);
      case 'consultant': return const Color(0xFF92400E);
      case 'leader': return const Color(0xFF1E3A5F);
      case 'analyst': return const Color(0xFF831843);
      default: return Colors.grey;
    }
  }

  String _formatLastSeen(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'agora';
      if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'há ${diff.inHours}h';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  bool _isRecentlyActive(String? iso) {
    if (iso == null) return false;
    try {
      final dt = DateTime.parse(iso);
      return DateTime.now().difference(dt).inMinutes < 15;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Usuários Online',
            style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirestoreService.streamPresence(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data ?? [];
          final online = all
              .where((u) =>
                  (u['online'] as bool? ?? false) ||
                  _isRecentlyActive(u['lastSeen'] as String?))
              .toList();
          final offline = all
              .where((u) =>
                  !(u['online'] as bool? ?? false) &&
                  !_isRecentlyActive(u['lastSeen'] as String?))
              .toList();

          if (all.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Nenhum usuário registrado.',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (online.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                          color: Colors.green, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text('Online (${online.length})',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                            fontSize: 13)),
                  ]),
                ),
                ...online.map((u) => _UserTile(
                    u: u,
                    online: true,
                    roleLabel: _roleLabel(u['role'] as String? ?? ''),
                    roleColor: _roleColor(u['role'] as String? ?? ''),
                    lastSeen: _formatLastSeen(u['lastSeen'] as String?))),
                const SizedBox(height: 16),
              ],
              if (offline.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text('Offline (${offline.length})',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                            fontSize: 13)),
                  ]),
                ),
                ...offline.map((u) => _UserTile(
                    u: u,
                    online: false,
                    roleLabel: _roleLabel(u['role'] as String? ?? ''),
                    roleColor: _roleColor(u['role'] as String? ?? ''),
                    lastSeen: _formatLastSeen(u['lastSeen'] as String?))),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final Map<String, dynamic> u;
  final bool online;
  final String roleLabel;
  final Color roleColor;
  final String lastSeen;

  const _UserTile({
    required this.u,
    required this.online,
    required this.roleLabel,
    required this.roleColor,
    required this.lastSeen,
  });

  @override
  Widget build(BuildContext context) {
    final name = (u['name'] as String?) ?? '';
    final team = (u['team'] as String?) ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: roleColor.withOpacity(0.15),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                    color: roleColor, fontWeight: FontWeight.bold),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: online ? Colors.green : Colors.grey.shade400,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            team.isNotEmpty ? '$roleLabel · $team' : roleLabel,
            style: TextStyle(color: roleColor, fontSize: 12)),
        trailing: Text(lastSeen,
            style:
                const TextStyle(color: Colors.grey, fontSize: 12)),
      ),
    );
  }
}
