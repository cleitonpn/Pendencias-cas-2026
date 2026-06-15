import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';

List<DateTime>? parseFairDateRange(String s, {int? year}) {
  year ??= DateTime.now().year;
  s = s.trim();
  if (s.isEmpty || s == 'N/A') return null;

  final m1 = RegExp(r'^(\d{1,2})\s*a\s*(\d{1,2})/(\d{1,2})$').firstMatch(s);
  if (m1 != null) {
    return [
      DateTime(year, int.parse(m1[3]!), int.parse(m1[1]!)),
      DateTime(year, int.parse(m1[3]!), int.parse(m1[2]!)),
    ];
  }
  final m2 =
      RegExp(r'^(\d{1,2})/(\d{1,2})\s*a\s*(\d{1,2})/(\d{1,2})$').firstMatch(s);
  if (m2 != null) {
    return [
      DateTime(year, int.parse(m2[2]!), int.parse(m2[1]!)),
      DateTime(year, int.parse(m2[4]!), int.parse(m2[3]!)),
    ];
  }
  final m3 = RegExp(r'^(\d{1,2})/(\d{1,2})$').firstMatch(s);
  if (m3 != null) {
    final d = DateTime(year, int.parse(m3[2]!), int.parse(m3[1]!));
    return [d, d];
  }
  return null;
}

class CronogramaScreen extends StatefulWidget {
  const CronogramaScreen({super.key});

  @override
  State<CronogramaScreen> createState() => _CronogramaScreenState();
}

class _CronogramaScreenState extends State<CronogramaScreen> {
  static const _blue = Color(0xFF3B82F6);
  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);
  static const _navy = Color(0xFF1E3A5F);

  bool _showAgenda = false;
  Map<int, Map<String, String>> _eventDates = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDates());
  }

  Future<void> _loadDates() async {
    final dates = await DatabaseService.getFairEventDates();
    if (mounted) {
      setState(() {
        _eventDates = dates;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allFairs = context.watch<AppProvider>().fairs;
    final fairs = allFairs.where((f) => f.sheetMode != 'mestra').toList()
      ..sort((a, b) {
        final da = _eventDates[a.id];
        final db = _eventDates[b.id];
        final ra = da != null ? parseFairDateRange((da['dataMontagem'] ?? '').trim()) : null;
        final rb = db != null ? parseFairDateRange((db['dataMontagem'] ?? '').trim()) : null;
        if (ra == null && rb == null) return 0;
        if (ra == null) return 1;
        if (rb == null) return -1;
        return ra.first.compareTo(rb.first);
      });

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Cronograma',
            style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(_showAgenda ? Icons.view_list : Icons.calendar_view_week),
            tooltip: _showAgenda ? 'Ver cards' : 'Ver agenda',
            onPressed: () => setState(() => _showAgenda = !_showAgenda),
          ),
        ],
        bottom: _showAgenda
            ? PreferredSize(
                preferredSize: const Size.fromHeight(32),
                child: _buildLegend(),
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _showAgenda
              ? _buildAgendaView(fairs)
              : _buildCardView(fairs),
    );
  }

  Widget _buildLegend() {
    return Container(
      color: _navy,
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Row(
        children: [
          _legendItem(_blue, 'Montagem'),
          const SizedBox(width: 16),
          _legendItem(_green, 'Evento'),
          const SizedBox(width: 16),
          _legendItem(_red, 'Desmontagem'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }

  Widget _buildCardView(List fairs) {
    if (fairs.isEmpty) {
      return const Center(
        child: Text('Nenhuma feira encontrada.',
            style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: fairs.length,
      itemBuilder: (context, index) {
        final fair = fairs[index];
        final dates = fair.id != null ? (_eventDates[fair.id] ?? <String, String>{}) : <String, String>{};
        return _buildFairCard(fair, dates);
      },
    );
  }

  Widget _buildFairCard(dynamic fair, Map<String, String> dates) {
    final borderColor = _modeColor(fair.mode as String);
    final pavilhao = (dates['pavilhao'] ?? '').trim();
    final montagem = (dates['dataMontagem'] ?? '').trim();
    final evento = (dates['dataEvento'] ?? '').trim();
    final desmontagem = (dates['dataDesmontagem'] ?? '').trim();
    final hasAnyDate =
        montagem.isNotEmpty || evento.isNotEmpty || desmontagem.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border(
          left: BorderSide(color: borderColor, width: 3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fair.name as String,
              style: const TextStyle(
                color: _navy,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            if (pavilhao.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                pavilhao,
                style: const TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (!hasAnyDate)
              const Text(
                'Sem datas cadastradas',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              )
            else ...[
              if (montagem.isNotEmpty)
                _dateRow(Icons.build_outlined,
                    const Color(0xFFF59E0B), 'Montagem', montagem),
              if (evento.isNotEmpty)
                _dateRow(Icons.event, _green, 'Evento', evento),
              if (desmontagem.isNotEmpty)
                _dateRow(Icons.local_shipping, _red, 'Desmontagem', desmontagem),
              _buildCountdownChip(montagem, desmontagem),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownChip(String montagem, String desmontagem) {
    final montagemRange = parseFairDateRange(montagem);
    final desmontagemRange = parseFairDateRange(desmontagem.isNotEmpty ? desmontagem : montagem);
    if (montagemRange == null) return const SizedBox.shrink();

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final startDate = montagemRange[0];
    final endDate = desmontagemRange != null ? desmontagemRange[1] : montagemRange[1];

    String label;
    Color chipColor;

    if (todayDate.isAfter(endDate)) {
      label = 'Encerrada';
      chipColor = Colors.grey;
    } else if (!todayDate.isBefore(startDate) && !todayDate.isAfter(endDate)) {
      label = 'Em andamento';
      chipColor = Colors.green;
    } else {
      final diff = startDate.difference(todayDate).inDays;
      if (diff == 0) {
        label = 'Hoje!';
        chipColor = Colors.amber.shade700;
      } else if (diff == 1) {
        label = 'Amanhã';
        chipColor = Colors.orange;
      } else {
        label = 'Em $diff dias';
        chipColor = Colors.blue;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: chipColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: chipColor.withOpacity(0.5)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: chipColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateRow(IconData icon, Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'producao':
        return _green;
      case 'manutencao':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _buildAgendaView(List fairs) {
    final dateColumns = _collectDateColumns(fairs);

    if (dateColumns.isEmpty) {
      return const Center(
        child: Text('Nenhuma data cadastrada para exibir na agenda.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAgendaHeader(dateColumns),
            ...fairs.map((fair) => _buildAgendaRow(fair, dateColumns)),
          ],
        ),
      ),
    );
  }

  List<DateTime> _collectDateColumns(List fairs) {
    final daySet = <DateTime>{};
    for (final fair in fairs) {
      final dates = fair.id != null ? (_eventDates[fair.id] ?? {}) : {};
      for (final key in ['dataMontagem', 'dataEvento', 'dataDesmontagem']) {
        final raw = (dates[key] ?? '').trim();
        if (raw.isEmpty) continue;
        final range = parseFairDateRange(raw);
        if (range == null) continue;
        var cur = range[0];
        final end = range[1];
        while (!cur.isAfter(end)) {
          daySet.add(DateTime(cur.year, cur.month, cur.day));
          cur = cur.add(const Duration(days: 1));
        }
      }
    }
    final sorted = daySet.toList()..sort();
    return sorted;
  }

  Widget _buildAgendaHeader(List<DateTime> dateColumns) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 110,
          height: 32,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _navy,
            border: Border(right: BorderSide(color: Colors.white24)),
          ),
          child: const Text(
            'Feira',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
        ...dateColumns.map((day) => _headerCell(day)),
      ],
    );
  }

  Widget _headerCell(DateTime day) {
    final label =
        '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
    return Container(
      width: 28,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _navy.withOpacity(0.85),
        border: Border(right: BorderSide(color: Colors.white12, width: 0.5)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 8),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildAgendaRow(dynamic fair, List<DateTime> dateColumns) {
    final dates = fair.id != null ? (_eventDates[fair.id] ?? {}) : {};

    final montagem =
        parseFairDateRange((dates['dataMontagem'] ?? '').trim());
    final evento =
        parseFairDateRange((dates['dataEvento'] ?? '').trim());
    final desmontagem =
        parseFairDateRange((dates['dataDesmontagem'] ?? '').trim());

    bool inRange(List<DateTime>? range, DateTime day) {
      if (range == null) return false;
      return !day.isBefore(range[0]) && !day.isAfter(range[1]);
    }

    Color? cellColor(DateTime day) {
      if (inRange(evento, day)) return _green;
      if (inRange(montagem, day)) return _blue;
      if (inRange(desmontagem, day)) return _red;
      return null;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 110,
          height: 32,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              right: BorderSide(color: Colors.grey.shade300),
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Text(
            fair.name as String,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: _navy),
          ),
        ),
        ...dateColumns.map((day) {
          final color = cellColor(day);
          return Container(
            width: 28,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.grey.shade200, width: 0.5),
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: color != null
                ? Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )
                : const SizedBox.shrink(),
          );
        }),
      ],
    );
  }
}
