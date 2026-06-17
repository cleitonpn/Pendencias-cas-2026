import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';
import 'circular_compose_screen.dart';

class CircularListScreen extends StatefulWidget {
  const CircularListScreen({super.key});

  @override
  State<CircularListScreen> createState() => _CircularListScreenState();
}

class _CircularListScreenState extends State<CircularListScreen> {
  static const _navy = Color(0xFF1E3A5F);
  bool _canCompose = false;

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    final session = await SessionService.get();
    if (!mounted) return;
    final role = session?['role'] ?? '';
    setState(() => _canCompose = role == 'admin' || role == 'manager');
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  String _groupLabel(String g) {
    switch (g) {
      case 'todos': return 'Todos';
      case 'produtores': return 'Produtores';
      case 'consultores': return 'Consultores';
      case 'lideres': return 'Líderes';
      case 'analistas': return 'Analistas';
      case 'admins': return 'Admins';
      default: return g;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('⚠️ Avisos',
            style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: _canCompose
          ? FloatingActionButton.extended(
              backgroundColor: _navy,
              icon: const Icon(Icons.edit, color: Colors.white),
              label: const Text('Novo Aviso',
                  style: TextStyle(color: Colors.white)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CircularComposeScreen()),
              ),
            )
          : null,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirestoreService.streamAvisos(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final avisos = snap.data ?? [];
          if (avisos.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.campaign_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Nenhum aviso publicado.',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: avisos.length,
            itemBuilder: (context, i) {
              final c = avisos[i];
              final title = (c['title'] as String?) ?? '';
              final body = (c['body'] as String?) ?? '';
              final createdBy = (c['createdBy'] as String?) ?? '';
              final createdAt = _formatDate(c['createdAt'] as String?);
              final groups = (c['targetGroups'] as List?)
                      ?.map((g) => _groupLabel(g.toString()))
                      .toList() ??
                  ['Todos'];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFFBFD5F7), width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('⚠️', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: _navy,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(body,
                            style: const TextStyle(
                                fontSize: 14, color: Colors.black87)),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        children: groups
                            .map((g) => Chip(
                                  label: Text(g,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: _navy)),
                                  backgroundColor:
                                      const Color(0xFFDEEAFD),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.person_outline,
                              size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(createdBy,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                          const Spacer(),
                          const Icon(Icons.access_time,
                              size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(createdAt,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
