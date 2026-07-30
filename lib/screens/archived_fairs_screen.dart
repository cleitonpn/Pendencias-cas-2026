import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/fair.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';

class ArchivedFairsScreen extends StatefulWidget {
  const ArchivedFairsScreen({super.key});
  @override
  State<ArchivedFairsScreen> createState() => _ArchivedFairsScreenState();
}

class _ArchivedFairsScreenState extends State<ArchivedFairsScreen> {
  static const _navy = Color(0xFF1E3A5F);
  List<Fair> _archived = [];
  /// Nomes que o admin mandou não trazer mais da planilha mestra. Ficam aqui
  /// porque este é o lugar onde já se desfaz o arquivamento — e sem um lugar
  /// para desfazer, "não trazer de volta" seria uma porta sem volta.
  List<Map<String, dynamic>> _ignored = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DatabaseService.getArchivedFairs();
    List<Map<String, dynamic>> ignored = [];
    try {
      ignored = await FirestoreService.getIgnoredFairs();
    } catch (_) {
      // Sem rede a tela ainda serve para as arquivadas.
    }
    if (mounted) {
      setState(() {
        _archived = list;
        _ignored = ignored;
        _loading = false;
      });
    }
  }

  Future<void> _unignore(Map<String, dynamic> e) async {
    await context.read<AppProvider>().unignoreFair(e['key'] as String);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${e['name']} volta a ser trazida na próxima '
                'sincronização.')),
      );
    }
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
    // Feira arquivada que veio da mestra volta no próximo sync se não for
    // marcada como ignorada — que é justamente o que se quer evitar ao
    // excluir definitivamente.
    final problema = await context
        .read<AppProvider>()
        .deleteFair(fair.id!, alsoIgnore: true);
    await _load();
    if (problema != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(problema), backgroundColor: Colors.red),
      );
    }
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
          : (_archived.isEmpty && _ignored.isEmpty)
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
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_archived.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Nenhuma feira arquivada.',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    ..._archived.map((fair) {
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
                    }),
                    if (_ignored.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Icon(Icons.block, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text('Não trazer da planilha (${_ignored.length})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, color: _navy)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Estas feiras existem na planilha mestra mas foram '
                        'excluídas do app. Sem isto o sync as recriaria a '
                        'cada sincronização.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      ..._ignored.map((e) => Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFF3F4F6),
                                child: Icon(Icons.block, color: Colors.grey),
                              ),
                              title: Text((e['name'] as String?) ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: const Text('Ignorada na sincronização',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                              trailing: TextButton(
                                onPressed: () => _unignore(e),
                                child: const Text('Voltar a trazer',
                                    style: TextStyle(color: _navy)),
                              ),
                            ),
                          )),
                    ],
                  ],
                ),
    );
  }
}
