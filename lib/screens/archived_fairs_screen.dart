import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/fair.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';

class ArchivedFairsScreen extends StatefulWidget {
  const ArchivedFairsScreen({super.key});
  @override
  State<ArchivedFairsScreen> createState() => _ArchivedFairsScreenState();
}

class _ArchivedFairsScreenState extends State<ArchivedFairsScreen> {
  static const _navy = Color(0xFF1E3A5F);
  List<Fair> _archived = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DatabaseService.getArchivedFairs();
    if (mounted) setState(() { _archived = list; _loading = false; });
  }

  Future<void> _restore(Fair fair) async {
    await context.read<AppProvider>().restoreFair(fair);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${fair.name} restaurada.')),
      );
    }
  }

  Future<void> _delete(Fair fair) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir definitivamente?'),
        content: Text('${fair.name} será removida permanentemente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppProvider>().deleteFair(fair.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Feiras Arquivadas', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _archived.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.archive_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('Nenhuma feira arquivada.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _archived.length,
                  itemBuilder: (context, i) {
                    final fair = _archived[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFE8F0FB),
                          child: Icon(Icons.archive_outlined, color: _navy),
                        ),
                        title: Text(fair.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Arquivada', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.unarchive_outlined, color: Colors.green),
                              tooltip: 'Restaurar',
                              onPressed: () => _restore(fair),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              tooltip: 'Excluir definitivamente',
                              onPressed: () => _delete(fair),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
