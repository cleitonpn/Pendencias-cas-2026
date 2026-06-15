import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/client.dart';
import '../services/database_service.dart';

class ProducerPerformanceScreen extends StatefulWidget {
  const ProducerPerformanceScreen({super.key});

  @override
  State<ProducerPerformanceScreen> createState() =>
      _ProducerPerformanceScreenState();
}

class _ProducerPerformanceScreenState
    extends State<ProducerPerformanceScreen> {
  Map<String, int> _pendingCounts = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final clients = context.read<AppProvider>().clients;
    final counts = await DatabaseService.getPendingCounts(
        clients.map((c) => c.rowId).toList());
    if (mounted) setState(() { _pendingCounts = counts; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    final clients = context.watch<AppProvider>().clients;
    final stats = _buildStats(clients);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
        title: const Text('Desempenho por Produtor',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : stats.isEmpty
              ? const Center(
                  child: Text('Nenhum produtor encontrado.',
                      style: TextStyle(color: Colors.grey, fontSize: 16)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: stats.length,
                  itemBuilder: (context, i) => _ProducerCard(stat: stats[i]),
                ),
    );
  }

  List<_ProducerStat> _buildStats(List<Client> clients) {
    final map = <String, List<Client>>{};
    for (final c in clients) {
      if (c.produtor.isEmpty) continue;
      map.putIfAbsent(c.produtor, () => []).add(c);
    }

    final stats = map.entries.map((e) {
      final pClients = e.value;
      final total = pClients.length;
      final completed = pClients.where((c) => c.isCompleted).length;
      final pending = pClients.fold<int>(
          0, (sum, c) => sum + (_pendingCounts[c.rowId] ?? 0));
      return _ProducerStat(
        name: e.key,
        total: total,
        completed: completed,
        openPending: pending,
      );
    }).toList();

    stats.sort((a, b) {
      final ra = a.total == 0 ? 0.0 : a.completed / a.total;
      final rb = b.total == 0 ? 0.0 : b.completed / b.total;
      return rb.compareTo(ra);
    });

    return stats;
  }
}

class _ProducerStat {
  final String name;
  final int total, completed, openPending;
  _ProducerStat(
      {required this.name,
      required this.total,
      required this.completed,
      required this.openPending});
  double get rate => total == 0 ? 0 : completed / total;
}

class _ProducerCard extends StatelessWidget {
  final _ProducerStat stat;
  const _ProducerCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    final rate = stat.rate;
    final Color color = rate == 1.0
        ? Colors.green
        : rate > 0
            ? Colors.orange
            : Colors.red.shade300;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(stat.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Text(
                  '${(rate * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: rate,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _chip('${stat.completed}/${stat.total} stands',
                    Colors.blue.shade700, Colors.blue.shade50),
                const SizedBox(width: 8),
                _chip(
                  stat.openPending == 0
                      ? 'Sem pendências'
                      : '${stat.openPending} pendência${stat.openPending > 1 ? 's' : ''}',
                  stat.openPending == 0
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                  stat.openPending == 0
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color text, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, color: text, fontWeight: FontWeight.w600)),
      );
}
