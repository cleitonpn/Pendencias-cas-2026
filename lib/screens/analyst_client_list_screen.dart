import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/client.dart';
import '../services/database_service.dart';
import 'analyst_client_detail_screen.dart';

class AnalystClientListScreen extends StatefulWidget {
  final String hangar;
  final String analystName;
  const AnalystClientListScreen(
      {super.key, required this.hangar, required this.analystName});

  @override
  State<AnalystClientListScreen> createState() =>
      _AnalystClientListScreenState();
}

class _AnalystClientListScreenState extends State<AnalystClientListScreen> {
  String _search = '';
  Map<String, int> _pendingCounts = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCounts());
  }

  Future<void> _loadCounts() async {
    final clients =
        context.read<AppProvider>().getClientsByHangar(widget.hangar);
    final counts = await DatabaseService.getPendingCounts(
        clients.map((c) => c.rowId).toList());
    if (mounted) setState(() => _pendingCounts = counts);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    var clients = provider.getClientsByHangar(widget.hangar);

    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      clients = clients
          .where((c) =>
              c.nome.toLowerCase().contains(q) ||
              c.local.contains(q) ||
              c.montagem.toLowerCase().contains(q))
          .toList();
    }

    clients = List.of(clients)
      ..sort((a, b) => a.local.compareTo(b.local));

    final completed = clients.where((c) => c.isCompleted).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Text('Hangar ${widget.hangar}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar stand ou cliente...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixIcon:
                    Icon(Icons.search, color: Colors.white.withOpacity(0.6)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _StatsBar(
              total: clients.length,
              completed: completed,
              pending: clients.length - completed),
          Expanded(
            child: clients.isEmpty
                ? const Center(
                    child: Text('Nenhum cliente encontrado.',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: clients.length,
                    itemBuilder: (context, i) => _ClientCard(
                      client: clients[i],
                      pendingCount: _pendingCounts[clients[i].rowId] ?? 0,
                      onTap: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => AnalystClientDetailScreen(
                                      client: clients[i],
                                      analystName: widget.analystName,
                                    )));
                        await _loadCounts();
                        setState(() {});
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final int total, completed, pending;
  const _StatsBar(
      {required this.total, required this.completed, required this.pending});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _chip('Total', total, Colors.blue),
          const SizedBox(width: 8),
          _chip('Concluídos', completed, Colors.green),
          const SizedBox(width: 8),
          _chip('Pendentes', pending, Colors.orange),
        ],
      ),
    );
  }

  Widget _chip(String label, int value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$value',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: color)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      );
}

class _ClientCard extends StatelessWidget {
  final Client client;
  final int pendingCount;
  final VoidCallback onTap;
  const _ClientCard(
      {required this.client,
      required this.pendingCount,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final done = client.isCompleted;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: done ? Colors.green.shade300 : Colors.grey.shade200),
      ),
      color: done ? Colors.green.shade50 : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: done
                      ? Colors.green.shade100
                      : const Color(0xFF1E3A5F).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check_circle,
                          color: Colors.green, size: 30)
                      : Text(
                          client.local.isEmpty ? '—' : client.local,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1E3A5F)),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client.displayName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    if (client.montagem.isNotEmpty)
                      Text(client.montagem,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12)),
                    // Tipo do stand: nas feiras grandes é o que a equipe
                    // procura primeiro. Escondido quando repetiria a
                    // montagem, como acontece nas feiras da planilha mestra.
                    if (client.tipo.isNotEmpty &&
                        client.tipo != client.montagem)
                      Text(client.tipo,
                          style: const TextStyle(
                              color: Color(0xFF1E3A5F),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    if (client.area.isNotEmpty)
                      Text('${client.area} m²',
                          style: const TextStyle(
                              color: Color(0xFF1E3A5F),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (done)
                const Text('Concluído',
                    style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w600))
              else if (pendingCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$pendingCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
