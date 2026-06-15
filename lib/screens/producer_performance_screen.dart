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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final clients = context.read<AppProvider>().clients;
    final ids = clients.map((c) => c.rowId).toList();
    final counts = await DatabaseService.getPendingCounts(ids);
    if (mounted) {
      setState(() {
        _pendingCounts = counts;
        _loading = false;
      });
    }
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : stats.isEmpty
              ? const Center(
                  child: Text('Nenhum produtor encontrado.',
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: stats.length,
                  itemBuilder: (context, i) =>
                      _ProducerCard(stat: stats[i]),
                ),
    );
  }

  List<_ProducerStat> _buildStats(List<Client> clients) {
    final Map<String, List<Client>> byProducer = {};
    for (final c in clients) {
      if (c.produtor.isEmpty) continue;
      byProducer.putIfAbsent(c.produtor, () => []).add(c);
    }

    final stats = byProducer.entries.map((entry) {
      final name = entry.key;
      final list = entry.value;
      final total = list.length;
      final completed = list.where((c) => c.isCompleted).length;
      final openPending = list.fold<int>(
        0,
        (sum, c) => sum + (_pendingCounts[c.rowId] ?? 0),
      );
      final rate = total > 0 ? completed / total : 0.0;
      return _ProducerStat(
        name: name,
        totalStands: total,
        completedStands: completed,
        openPending: openPending,
        completionRate: rate,
      );
    }).toList()
      ..sort((a, b) => b.completionRate.compareTo(a.completionRate));

    return stats;
  }
}

class _ProducerStat {
  final String name;
  final int totalStands;
  final int completedStands;
  final int openPending;
  final double completionRate;

  const _ProducerStat({
    required this.name,
    required this.totalStands,
    required this.completedStands,
    required this.openPending,
    required this.completionRate,
  });
}

class _ProducerCard extends StatelessWidget {
  final _ProducerStat stat;

  const _ProducerCard({required this.stat});

  Color get _borderColor {
    if (stat.completionRate >= 1.0) return Colors.green;
    if (stat.completionRate > 0.0) return Colors.orange;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _borderColor;
    final progressColor = stat.completionRate >= 1.0
        ? Colors.green
        : stat.completionRate > 0.0
            ? Colors.orange
            : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stat.name,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E3A5F),
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: stat.completionRate,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _StatChip(
                  label: '${stat.completedStands}/${stat.totalStands} stands',
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  label: stat.openPending == 0
                      ? '0 pendências'
                      : '${stat.openPending} pendências',
                  color: stat.openPending == 0 ? Colors.green : Colors.orange,
                ),
                const Spacer(),
                Text(
                  '${(stat.completionRate * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: progressColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600),
        ),
      );
}
