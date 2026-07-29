import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pending_item.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';
import '../widgets/pending_status.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late int _fairId;
  List<PendingItem> _open = [];
  List<PendingItem> _resolved = [];
  List<PendingItem> _rejected = [];
  Map<String, int> _stats = {};
  List<Map<String, dynamic>> _teamRankings = [];
  List<Map<String, dynamic>> _producerRankings = [];
  List<Map<String, dynamic>> _leaderRankings = [];
  List<Map<String, dynamic>> _crossFair = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fairId = context.read<AppProvider>().currentFair?.id ?? 1;
    _tab = TabController(length: 8, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _open = await DatabaseService.getAllPendingItems(
        resolved: false, fairId: _fairId);
    // Recusadas vêm com is_resolved = 1; separá-las evita que apareçam
    // como resolvidas na aba e nas contagens.
    final closed = await DatabaseService.getAllPendingItems(
        resolved: true, fairId: _fairId);
    _resolved = closed.where((i) => !i.isRejected).toList();
    _rejected = closed.where((i) => i.isRejected).toList();
    _stats = await DatabaseService.getStats(fairId: _fairId);
    _teamRankings =
        await DatabaseService.getTeamRankings(fairId: _fairId);
    _producerRankings =
        await DatabaseService.getProducerRankings(fairId: _fairId);
    _leaderRankings =
        await DatabaseService.getLeaderRankings(fairId: _fairId);
    _crossFair = await DatabaseService.getCrossFairStats();
    setState(() => _loading = false);
  }

  Future<void> _openRanking(String name, RankingKind kind) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RankingDetailScreen(
            fairId: _fairId, name: name, kind: kind),
      ),
    );
    await _load(); // itens podem ter sido resolvidos lá dentro
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Relatórios',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorColor: Colors.orange,
          isScrollable: true,
          tabs: [
            Tab(text: 'Abertas (${_open.length})'),
            Tab(text: 'Resolvidas (${_resolved.length})'),
            Tab(text: 'Recusadas (${_rejected.length})'),
            const Tab(text: 'Resumo'),
            const Tab(text: 'Por Equipe'),
            const Tab(text: 'Por Produtor'),
            const Tab(text: 'Por Líder'),
            const Tab(text: 'Comparativo'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _ListTab(
                  items: _open,
                  emptyMsg: 'Nenhuma pendência aberta!',
                  emptyIcon: Icons.check_circle_outline,
                  emptyColor: Colors.green,
                  showResolved: false,
                  onExport: () => PdfService.generateAndShow(context,
                      () => PdfService.generatePendingReport(
                          _open, PendingReportKind.abertas)),
                  onReload: _load,
                ),
                _ListTab(
                  items: _resolved,
                  emptyMsg: 'Nenhuma pendência resolvida ainda.',
                  emptyIcon: Icons.pending_actions,
                  emptyColor: Colors.grey,
                  showResolved: true,
                  onExport: () => PdfService.generateAndShow(context,
                      () => PdfService.generatePendingReport(
                          _resolved, PendingReportKind.resolvidas)),
                  onReload: null,
                ),
                _ListTab(
                  items: _rejected,
                  emptyMsg: 'Nenhum chamado recusado.',
                  emptyIcon: Icons.cancel_outlined,
                  emptyColor: Colors.red,
                  showResolved: true,
                  onExport: () => PdfService.generateAndShow(context,
                      () => PdfService.generatePendingReport(
                          _rejected, PendingReportKind.recusadas)),
                  onReload: null,
                ),
                _SummaryTab(
                  stats: _stats,
                  resolved: _resolved,
                  onExport: () => PdfService.generateAndShow(context,
                      () => PdfService.generateSummaryReport(_stats, _resolved)),
                ),
                _RankingTab(
                  data: _teamRankings,
                  nameKey: 'team',
                  emptyMsg: 'Nenhuma pendência registrada.',
                  title: 'RANKING POR EQUIPE',
                  showAvgTime: true,
                  onTapItem: (name) => _openRanking(name, RankingKind.team),
                ),
                _RankingTab(
                  data: _producerRankings,
                  nameKey: 'producer',
                  emptyMsg: 'Nenhuma pendência com produtor registrado.',
                  title: 'RANKING POR PRODUTOR',
                  onTapItem: (name) =>
                      _openRanking(name, RankingKind.producer),
                ),
                _RankingTab(
                  data: _leaderRankings,
                  nameKey: 'leader',
                  emptyMsg: 'Nenhuma pendência com responsável definido.',
                  title: 'RANKING POR LÍDER',
                  showAvgTime: true,
                  onTapItem: (name) => _openRanking(name, RankingKind.leader),
                ),
                _CrossFairTab(data: _crossFair),
              ],
            ),
    );
  }
}

class _ListTab extends StatelessWidget {
  final List<PendingItem> items;
  final String emptyMsg;
  final IconData emptyIcon;
  final Color emptyColor;
  final bool showResolved;
  final Future<void> Function() onExport;
  final VoidCallback? onReload;

  const _ListTab({
    required this.items,
    required this.emptyMsg,
    required this.emptyIcon,
    required this.emptyColor,
    required this.showResolved,
    required this.onExport,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Exportar PDF'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white),
              ),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(emptyIcon, size: 64, color: emptyColor),
                      const SizedBox(height: 12),
                      Text(emptyMsg,
                          style: TextStyle(
                              color: emptyColor, fontSize: 16)),
                    ],
                  ),
                )
              : _GroupedList(items: items, onReload: onReload),
        ),
      ],
    );
  }
}

class _GroupedList extends StatelessWidget {
  final List<PendingItem> items;
  final VoidCallback? onReload;

  const _GroupedList({required this.items, required this.onReload});

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<PendingItem>>{};
    for (final item in items) {
      final key = item.hangar.isNotEmpty
          ? 'Hangar ${item.hangar}'
          : 'Sem Hangar';
      grouped.putIfAbsent(key, () => []).add(item);
    }
    final keys = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final key = keys[i];
        final group = grouped[key]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(key,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E3A5F),
                      fontSize: 14)),
            ),
            ...group.map((item) =>
                _ItemCard(item: item, onReload: onReload)),
          ],
        );
      },
    );
  }
}

class _ItemCard extends StatelessWidget {
  final PendingItem item;
  final VoidCallback? onReload;

  const _ItemCard({required this.item, required this.onReload});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Stand ${item.local} — ${item.clientName}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(item.team,
                      style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(item.description,
                style: const TextStyle(fontSize: 13)),
            if (item.isRejected) ...[
              const SizedBox(height: 4),
              PendingStatusBadge(item: item, fontSize: 11),
              PendingNotes(item: item),
            ],
            const SizedBox(height: 4),
            Text(_fmt(item.createdAt),
                style:
                    const TextStyle(color: Colors.grey, fontSize: 11)),
            if (item.resolvedAt != null)
              Text(
                'Resolvido: ${_fmt(item.resolvedAt!)} '
                '(${_dur(item.resolvedAt!.difference(item.createdAt))})',
                style: const TextStyle(
                    color: Colors.green, fontSize: 11),
              ),
            if (onReload != null && !item.isResolved) ...[
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  // Antes gravava só no SQLite: a resolução ficava presa neste
                  // aparelho e os outros continuavam vendo a pendência aberta.
                  await context.read<AppProvider>().resolveItem(
                        item.id!,
                        firestoreId: item.firestoreId,
                        by: 'Administrador',
                      );
                  onReload!();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Marcar como Resolvido',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _dur(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}min';
    return '${d.inMinutes}min';
  }
}

class _SummaryTab extends StatelessWidget {
  final Map<String, int> stats;
  final List<PendingItem> resolved;
  final Future<void> Function() onExport;

  const _SummaryTab(
      {required this.stats,
      required this.resolved,
      required this.onExport});

  @override
  Widget build(BuildContext context) {
    Duration total = Duration.zero;
    int cnt = 0;
    for (final item in resolved) {
      if (item.resolvedAt != null) {
        total += item.resolvedAt!.difference(item.createdAt);
        cnt++;
      }
    }
    final avg = cnt > 0
        ? Duration(minutes: total.inMinutes ~/ cnt)
        : Duration.zero;

    final byTeam = <String, int>{};
    for (final item in resolved) {
      byTeam[item.team] = (byTeam[item.team] ?? 0) + 1;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Exportar Relatório Final PDF'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 20),
          const Text('VISÃO GERAL',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1)),
          const SizedBox(height: 8),
          _row('Total de stands', '${stats['total'] ?? 0}',
              Icons.grid_on, Colors.blue),
          _row('Concluídos', '${stats['completed'] ?? 0}',
              Icons.check_circle, Colors.green),
          _row('Com pendências', '${stats['with_pending'] ?? 0}',
              Icons.warning_amber, Colors.orange),
          _row('Pendências abertas', '${stats['total_pending'] ?? 0}',
              Icons.pending, Colors.red),
          _row('Pendências resolvidas',
              '${stats['resolved_pending'] ?? 0}',
              Icons.done_all, Colors.green),
          if ((stats['rejected_pending'] ?? 0) > 0)
            _row('Chamados recusados',
                '${stats['rejected_pending'] ?? 0}',
                Icons.cancel, Colors.red),
          _row('Tempo médio de resolução', _dur(avg), Icons.timer,
              Colors.purple),
          if (byTeam.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('RESOLVIDAS POR EQUIPE',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 8),
            ...byTeam.entries.map((e) =>
                _row(e.key, '${e.value}', Icons.group, Colors.indigo)),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, IconData icon, Color color) =>
      Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(label,
                      style: const TextStyle(fontSize: 14))),
              Text(value,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
        ),
      );

  String _dur(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}min';
    return '${d.inMinutes}min';
  }
}

class _RankingTab extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final String nameKey;
  final String emptyMsg;
  final String title;
  final bool showAvgTime;
  final void Function(String name)? onTapItem;

  const _RankingTab({
    required this.data,
    required this.nameKey,
    required this.emptyMsg,
    required this.title,
    this.showAvgTime = false,
    this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bar_chart, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text(emptyMsg,
                style: const TextStyle(color: Colors.grey, fontSize: 16),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final maxTotal = data.first['total'] as int;

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: data.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
          );
        }
        final item = data[i - 1];
        final name = item[nameKey] as String;
        final total = (item['total'] as num?)?.toInt() ?? 0;
        final open = (item['open'] as num?)?.toInt() ?? 0;
        final resolved = (item['resolved'] as num?)?.toInt() ?? 0;
        final rejected = (item['rejected'] as num?)?.toInt() ?? 0;
        final progress = maxTotal > 0 ? total / maxTotal : 0.0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTapItem == null ? null : () => onTapItem!(name),
            child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A5F).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('$i',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Color(0xFF1E3A5F))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15))),
                  Text('$total',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E3A5F))),
                  if (onTapItem != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.chevron_right,
                          color: Colors.grey, size: 20),
                    ),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF1E3A5F)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  _chip('$open abertas', Colors.orange),
                  const SizedBox(width: 8),
                  _chip('$resolved resolvidas', Colors.green),
                  if (rejected > 0) ...[
                    const SizedBox(width: 8),
                    _chip('$rejected recusadas', Colors.red),
                  ],
                  if (showAvgTime) ...[
                    const SizedBox(width: 8),
                    _avgTimeChip(item['avg_minutes']),
                  ],
                ]),
              ],
            ),
            ),
          ),
        );
      },
    );
  }

  Widget _avgTimeChip(dynamic avgMinutes) {
    if (avgMinutes == null) return const SizedBox.shrink();
    final mins = (avgMinutes as num).round();
    final d = Duration(minutes: mins);
    String label;
    if (d.inDays > 0) {
      label = '⌀ ${d.inDays}d ${d.inHours % 24}h';
    } else if (d.inHours > 0) {
      label = '⌀ ${d.inHours}h${d.inMinutes % 60}min';
    } else {
      label = '⌀ ${d.inMinutes}min';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withOpacity(0.3)),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11,
              color: Colors.purple,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600)),
      );
}

/// Como o nome do ranking se relaciona com a pendência.
enum RankingKind { team, producer, leader }

/// Pendências de uma equipe, produtor ou líder, aberta ao tocar num card do
/// ranking.
class RankingDetailScreen extends StatefulWidget {
  final int fairId;
  final String name;
  final RankingKind kind;

  const RankingDetailScreen({
    super.key,
    required this.fairId,
    required this.name,
    required this.kind,
  });

  @override
  State<RankingDetailScreen> createState() => _RankingDetailScreenState();
}

class _RankingDetailScreenState extends State<RankingDetailScreen> {
  List<PendingItem> _open = [];
  List<PendingItem> _resolved = [];
  List<PendingItem> _rejected = [];
  bool _loading = true;
  int _view = 0; // 0 abertas, 1 resolvidas, 2 recusadas

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Cada ranking agrupa por um campo diferente; o filtro precisa usar
  /// exatamente o mesmo, senão a lista mostra um número diferente do card.
  /// O de produtor agrupa por `clients.produtor` (via JOIN), não por
  /// `pending_items.producerName` — por isso é resolvido pelo cliente.
  bool _matches(PendingItem item) {
    switch (widget.kind) {
      case RankingKind.team:
        return item.team == widget.name;
      case RankingKind.leader:
        return item.responsible == widget.name;
      case RankingKind.producer:
        final client = context.read<AppProvider>().clientById(item.clientId);
        return client?.produtor == widget.name;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final open = await DatabaseService.getAllPendingItems(
        resolved: false, fairId: widget.fairId);
    final resolved = await DatabaseService.getAllPendingItems(
        resolved: true, fairId: widget.fairId);
    if (!mounted) return;
    setState(() {
      _open = open.where(_matches).toList();
      // Recusadas vêm com is_resolved = 1; separadas para não contarem
      // como resolvidas.
      final closed = resolved.where(_matches).toList();
      _resolved = closed.where((i) => !i.isRejected).toList();
      _rejected = closed.where((i) => i.isRejected).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _view == 0
        ? _open
        : _view == 1
            ? _resolved
            : _rejected;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.name,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            Text(
                widget.kind == RankingKind.team
                    ? 'Equipe'
                    : widget.kind == RankingKind.leader
                        ? 'Líder responsável'
                        : 'Produtor',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7), fontSize: 12)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(children: [
                    _tab('Abertas', _open.length, Colors.orange, _view == 0,
                        () => setState(() => _view = 0)),
                    const SizedBox(width: 8),
                    _tab('Resolvidas', _resolved.length, Colors.green,
                        _view == 1, () => setState(() => _view = 1)),
                    if (_rejected.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _tab('Recusadas', _rejected.length, Colors.red,
                          _view == 2, () => setState(() => _view = 2)),
                    ],
                  ]),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            _view == 0
                                ? 'Nenhuma pendência aberta.'
                                : _view == 1
                                    ? 'Nenhuma pendência resolvida.'
                                    : 'Nenhum chamado recusado.',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : _GroupedList(
                          items: items,
                          onReload: _view == 0 ? _load : null,
                        ),
                ),
              ],
            ),
    );
  }

  Widget _tab(String label, int count, Color color, bool selected,
          VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? color : color.withOpacity(0.3),
                width: 1.5),
          ),
          child: Text('$count $label',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : color)),
        ),
      );
}

class _CrossFairTab extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _CrossFairTab({required this.data});

  String _dur(dynamic mins) {
    if (mins == null) return '—';
    final d = Duration(minutes: (mins as num).round());
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}min';
    return '${d.inMinutes}min';
  }

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.compare_arrows, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text('Nenhuma feira cadastrada.',
              style: TextStyle(color: Colors.grey, fontSize: 16)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: data.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('COMPARATIVO ENTRE FEIRAS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
          );
        }
        final row = data[i - 1];
        final name = row['fair_name'] as String? ?? '—';
        final total = (row['total_clients'] as num?)?.toInt() ?? 0;
        final completed = (row['completed_clients'] as num?)?.toInt() ?? 0;
        final pct = total > 0 ? completed / total : 0.0;
        final totalPend = (row['total_pending'] as num?)?.toInt() ?? 0;
        final resolved = (row['resolved_pending'] as num?)?.toInt() ?? 0;
        final color = pct == 1.0
            ? Colors.green
            : pct > 0.5
                ? Colors.orange
                : const Color(0xFF1E3A5F);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _stat('Stands', '$completed/$total',
                        Icons.grid_on, color),
                  ),
                  Expanded(
                    child: _stat('Pendências', '$resolved/$totalPend',
                        Icons.pending_actions, Colors.orange),
                  ),
                  Expanded(
                    child: _stat('Tempo médio', _dur(row['avg_minutes']),
                        Icons.timer, Colors.purple),
                  ),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${(pct * 100).round()}% concluído',
                    style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) =>
      Column(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: color)),
        Text(label,
            style:
                const TextStyle(fontSize: 10, color: Colors.grey)),
      ]);
}
