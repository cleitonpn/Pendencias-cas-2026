import 'package:flutter/material.dart';
import '../models/freight_request.dart';
import '../services/firestore_service.dart';

class FreightReportScreen extends StatefulWidget {
  final int fairId;
  final String fairName;

  const FreightReportScreen({
    super.key,
    required this.fairId,
    required this.fairName,
  });

  @override
  State<FreightReportScreen> createState() => _FreightReportScreenState();
}

class _FreightReportScreenState extends State<FreightReportScreen> {
  List<FreightRequest> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list =
          await FirestoreService.getFreightRequestsForReport(widget.fairId);
      if (mounted) setState(() { _requests = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  String _fmtDuration(Duration? d) {
    if (d == null) return '—';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h == 0) return '${m}min';
    return '${h}h ${m}min';
  }

  Duration? _between(String? from, String? to) {
    if (from == null || from.isEmpty || to == null || to.isEmpty) return null;
    try {
      final f = DateTime.parse(from);
      final t = DateTime.parse(to);
      return t.difference(f);
    } catch (_) {
      return null;
    }
  }

  String _avgDuration(List<Duration> durations) {
    if (durations.isEmpty) return '—';
    final total = durations.fold<int>(
        0, (sum, d) => sum + d.inMinutes);
    final avg = Duration(minutes: (total / durations.length).round());
    return _fmtDuration(avg);
  }

  String _fmtIso(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  static const _motivoLabels = {
    'montagem': 'Montagem',
    'desmontagem': 'Desmontagem',
    'sobra': 'Sobra',
    'extra': 'Extra',
    'itens_faltantes': 'Itens Faltantes',
    'outros': 'Outros',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.fairName,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const Text('Relatório de Logística',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Atualizar',
            onPressed: () {
              setState(() { _loading = true; _error = null; });
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text('Erro: $_error',
                      style: const TextStyle(color: Colors.red)))
              : _build(),
    );
  }

  Widget _build() {
    if (_requests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_outlined, size: 72, color: Colors.grey),
            SizedBox(height: 16),
            Text('Nenhuma solicitação finalizada',
                style: TextStyle(color: Colors.grey, fontSize: 18)),
          ],
        ),
      );
    }

    // Compute SLAs
    final slaAccept = _requests
        .map((r) => _between(r.requestedAt, r.scheduledAt))
        .whereType<Duration>()
        .toList();
    final slaDispatch = _requests
        .map((r) => _between(r.scheduledAt, r.dispatchedAt))
        .whereType<Duration>()
        .toList();
    final slaDelivery = _requests
        .map((r) => _between(r.dispatchedAt, r.finalizedAt))
        .whereType<Duration>()
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary card
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('RESUMO',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 1)),
                const SizedBox(height: 12),
                _SummaryRow(
                    label: 'Total finalizado',
                    value: '${_requests.length} solicitações'),
                const Divider(height: 16),
                _SummaryRow(
                    label: 'Média: Em aberto → Agendado',
                    value: _avgDuration(slaAccept)),
                _SummaryRow(
                    label: 'Média: Agendado → Despachado',
                    value: _avgDuration(slaDispatch)),
                _SummaryRow(
                    label: 'Média: Despachado → Finalizado',
                    value: _avgDuration(slaDelivery)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        const Text('DETALHAMENTO',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1)),
        const SizedBox(height: 8),

        ..._requests.map((r) {
          final dAccept = _between(r.requestedAt, r.scheduledAt);
          final dDispatch = _between(r.scheduledAt, r.dispatchedAt);
          final dDelivery = _between(r.dispatchedAt, r.finalizedAt);

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade700,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('#${r.number}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r.clientNames.isEmpty ? 'Toda a feira' : r.clientNames.join(', '),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (r.motivos.isNotEmpty)
                    Text(
                      r.motivos
                          .map((m) => _motivoLabels[m] ?? m)
                          .join(' · '),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  const SizedBox(height: 8),
                  _slaRow('Solicitado', _fmtIso(r.requestedAt)),
                  _slaRow('Agendado', _fmtIso(r.scheduledAt),
                      duration: dAccept, durationLabel: 'aceite'),
                  _slaRow('Despachado', _fmtIso(r.dispatchedAt),
                      duration: dDispatch, durationLabel: 'despacho'),
                  _slaRow('Finalizado', _fmtIso(r.finalizedAt),
                      duration: dDelivery, durationLabel: 'entrega'),
                  if (r.handledBy.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Responsável: ${r.handledBy}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.blueGrey)),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _slaRow(String label, String value,
      {Duration? duration, String? durationLabel}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500)),
          if (duration != null && durationLabel != null) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_fmtDuration(duration)} ($durationLabel)',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.teal.shade800,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: Colors.black87))),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A5F))),
        ],
      ),
    );
  }
}
