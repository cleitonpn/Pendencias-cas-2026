import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';

/// "Visão de guerra" — painel operacional em tempo real da feira.
/// Ideal para deixar aberto no celular ou num tablet/TV no galpão.
/// Atualiza automaticamente a cada 30 segundos.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _timer;
  Map<String, int> _stats = {};
  List<Map<String, dynamic>> _teamRankings = [];
  Set<String> _sentPhotoToday = {};
  bool _loading = true;
  DateTime? _lastRefresh;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = context.read<AppProvider>();
    final fairId = provider.currentFair?.id;
    final fairName = provider.currentFairName;
    if (fairId == null) return;

    final stats = await DatabaseService.getStats(fairId: fairId);
    final teams = await DatabaseService.getTeamRankings(fairId: fairId);
    final sent = await FirestoreService.getMontageProducersToday(fairName);

    if (mounted) {
      setState(() {
        _stats = stats;
        _teamRankings = teams;
        _sentPhotoToday = sent;
        _loading = false;
        _lastRefresh = DateTime.now();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final clients = provider.clients;
    final fairName = provider.currentFairName;

    final total = _stats['total'] ?? 0;
    final completed = _stats['completed'] ?? 0;
    final totalPending = _stats['total_pending'] ?? 0;
    final progress = total > 0 ? completed / total : 0.0;

    // Distinct producers from client list
    final producers = clients
        .map((c) => c.produtor)
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fairName,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            if (_lastRefresh != null)
              Text(
                'Atualizado às ${_fmt(_lastRefresh!)} · auto 30s',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 11),
              ),
          ],
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _load,
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Progresso geral ──────────────────────────────────────
                  _SectionLabel('PROGRESSO DA FEIRA'),
                  const SizedBox(height: 8),
                  _ProgressCard(
                      total: total,
                      completed: completed,
                      progress: progress,
                      totalPending: totalPending),
                  const SizedBox(height: 20),

                  // ── Pendências por equipe ────────────────────────────────
                  _SectionLabel('PENDÊNCIAS POR EQUIPE'),
                  const SizedBox(height: 8),
                  if (_teamRankings.isEmpty)
                    _EmptyCard('Nenhuma pendência registrada.')
                  else
                    ..._teamRankings.map((r) => _TeamRow(data: r)),
                  const SizedBox(height: 20),

                  // ── Produtores: foto do dia ──────────────────────────────
                  _SectionLabel(
                      'PRODUTORES — FOTO DO DIA (${_sentPhotoToday.length}/${producers.length})'),
                  const SizedBox(height: 8),
                  if (producers.isEmpty)
                    _EmptyCard('Nenhum produtor encontrado na planilha.')
                  else
                    _ProducerGrid(
                        producers: producers,
                        sentToday: _sentPhotoToday),
                ],
              ),
            ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ── Widgets privados ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white54,
            letterSpacing: 1.2),
      );
}

class _EmptyCard extends StatelessWidget {
  final String msg;
  const _EmptyCard(this.msg);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(msg,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
      );
}

class _ProgressCard extends StatelessWidget {
  final int total;
  final int completed;
  final double progress;
  final int totalPending;

  const _ProgressCard({
    required this.total,
    required this.completed,
    required this.progress,
    required this.totalPending,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).round();
    final color = progress == 1.0
        ? Colors.greenAccent
        : progress > 0.6
            ? Colors.orangeAccent
            : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$completed / $total stands concluídos',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '$pct%',
                style: TextStyle(
                    color: color,
                    fontSize: 32,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            _statChip(
                '$totalPending', 'pendências abertas', Colors.orangeAccent),
            const SizedBox(width: 10),
            _statChip('${total - completed}', 'stands pendentes',
                Colors.redAccent),
          ]),
        ],
      ),
    );
  }

  Widget _statChip(String value, String label, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(color: color.withOpacity(0.8), fontSize: 12)),
        ]),
      );
}

class _TeamRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TeamRow({required this.data});

  Color get _teamColor {
    final t = (data['team'] as String? ?? '').toLowerCase();
    if (t.contains('elétr') || t.contains('eletr')) return Colors.orangeAccent;
    if (t.contains('marcenar')) return Colors.brown.shade300;
    if (t.contains('tapec')) return Colors.purpleAccent;
    if (t.contains('limpeza')) return Colors.cyanAccent;
    if (t.contains('comunic')) return Colors.pinkAccent;
    if (t.contains('vidrac')) return Colors.lightBlueAccent;
    return Colors.white70;
  }

  @override
  Widget build(BuildContext context) {
    final team = data['team'] as String? ?? '—';
    final open = (data['open'] as num?)?.toInt() ?? 0;
    final resolved = (data['resolved'] as num?)?.toInt() ?? 0;
    final total = (data['total'] as num?)?.toInt() ?? 1;
    final resolvedPct = total > 0 ? resolved / total : 0.0;
    final color = _teamColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(children: [
            Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(team,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            ),
            if (open > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$open abertas',
                    style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 8),
            Text('$resolved/$total',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: resolvedPct,
              minHeight: 4,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProducerGrid extends StatelessWidget {
  final List<String> producers;
  final Set<String> sentToday;

  const _ProducerGrid(
      {required this.producers, required this.sentToday});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.8,
      ),
      itemCount: producers.length,
      itemBuilder: (_, i) {
        final name = producers[i];
        final sent = sentToday.contains(name);
        final color =
            sent ? Colors.greenAccent : Colors.orangeAccent;
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Row(children: [
            Icon(
                sent
                    ? Icons.check_circle_outline
                    : Icons.photo_camera_outlined,
                color: color,
                size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name.split(' ').first,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        );
      },
    );
  }
}
