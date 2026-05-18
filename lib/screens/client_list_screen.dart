import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/client.dart';
import 'client_detail_screen.dart';

class ClientListScreen extends StatefulWidget {
  final String hangar;
  const ClientListScreen({super.key, required this.hangar});

  @override
  State<ClientListScreen> createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    var clients = provider.getClientsByHangar(widget.hangar);

    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      clients = clients
          .where((c) =>
              c.nome.toLowerCase().contains(q) ||
              c.stand.contains(q) ||
              c.montagem.toLowerCase().contains(q))
          .toList();
    }

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
                hintStyle:
                    TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixIcon: Icon(Icons.search,
                    color: Colors.white.withOpacity(0.6)),
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
                      onTap: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ClientDetailScreen(
                                    client: clients[i])));
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
      {required this.total,
      required this.completed,
      required this.pending});

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
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$value',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: color)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      );
}

class _ClientCard extends StatelessWidget {
  final Client client;
  final VoidCallback onTap;

  const _ClientCard({required this.client, required this.onTap});

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
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          client.stand.isEmpty ? '—' : client.stand,
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
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    if (client.montagem.isNotEmpty)
                      Text(client.montagem,
                          style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12)),
                  ],
                ),
              ),
              if (done)
                const Text('Concluído',
                    style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
