import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/pending_item.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';

class TeamLeaderPendingListScreen extends StatefulWidget {
  final String leaderName;
  final String team;
  const TeamLeaderPendingListScreen(
      {super.key, required this.leaderName, required this.team});

  @override
  State<TeamLeaderPendingListScreen> createState() =>
      _TeamLeaderPendingListScreenState();
}

class _TeamLeaderPendingListScreenState
    extends State<TeamLeaderPendingListScreen> {
  List<PendingItem> _items = [];
  Set<String> _awaitingFirestoreIds = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final fairId = context.read<AppProvider>().currentFair?.id ?? 1;
    final items = await DatabaseService.getPendingItemsByTeam(
        widget.team, fairId: fairId);
    // Load awaiting IDs from Firestore
    final awaitingSnapshot =
        await FirestoreService.getPendingItemsByTeam(widget.team);
    final awaitingIds = awaitingSnapshot
        .where((i) => i.awaitingValidation && !i.isResolved)
        .map((i) => i.firestoreId ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    if (mounted) {
      setState(() {
        _items = items;
        _awaitingFirestoreIds = awaitingIds;
        _loading = false;
      });
    }
  }

  bool _isAwaiting(PendingItem item) =>
      item.firestoreId != null &&
      _awaitingFirestoreIds.contains(item.firestoreId);

  Future<void> _markAwaiting(PendingItem item) async {
    await context
        .read<AppProvider>()
        .markItemAwaitingValidation(item.id!, firestoreId: item.firestoreId);
    await _load();
  }

  void _copyWhatsApp(PendingItem item) {
    Clipboard.setData(ClipboardData(text: item.toWhatsAppText()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Texto copiado! Cole no WhatsApp.'),
        backgroundColor: Color(0xFF25D366),
        duration: Duration(seconds: 3)));
  }

  // Group items by hangar
  Map<String, List<PendingItem>> get _grouped {
    final map = <String, List<PendingItem>>{};
    for (final item in _items) {
      final h = item.hangar.isEmpty ? 'Externos' : item.hangar;
      (map[h] ??= []).add(item);
    }
    return map;
  }

  // Within each hangar, group by client (local + clientName)
  Map<String, List<PendingItem>> _groupByClient(List<PendingItem> items) {
    final map = <String, List<PendingItem>>{};
    for (final item in items) {
      final key = '${item.local}|${item.clientName}';
      (map[key] ??= []).add(item);
    }
    return map;
  }

  Color get _teamColor {
    switch (widget.team.toLowerCase()) {
      case 'elétrica':
      case 'eletrica':
        return Colors.orange;
      case 'limpeza':
        return Colors.cyan.shade700;
      case 'marcenaria':
        return Colors.brown;
      case 'tapeçaria':
      case 'tapecaria':
        return Colors.purple;
      case 'vidraceiro':
        return Colors.lightBlue;
      case 'comunicação visual':
      case 'comunicacao visual':
        return Colors.pink;
      default:
        return const Color(0xFF1E3A5F);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final grouped = _grouped;
    final hangars = grouped.keys.toList()..sort();
    final openCount = _items.where((i) => !_isAwaiting(i)).length;
    final awaitingCount = _items.where(_isAwaiting).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: _teamColor,
        title: Text(widget.team,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: provider.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.sync, color: Colors.white),
            tooltip: 'Sincronizar',
            onPressed: provider.isLoading
                ? null
                : () async {
                    await context.read<AppProvider>().syncFromSheets();
                    await _load();
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          // Sync status bar
          if (provider.lastSync != null)
            Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.cloud_done, size: 14, color: Colors.green),
                  const SizedBox(width: 6),
                  Text(
                    'Última sync: ${DateFormat('dd/MM HH:mm').format(provider.lastSync!)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          // Stats bar
          Container(
            color: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _chip('Abertas', openCount, Colors.orange),
                const SizedBox(width: 8),
                _chip('Aguardando', awaitingCount, Colors.blue),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 64, color: Colors.green),
                            SizedBox(height: 12),
                            Text('Nenhuma pendência aberta!',
                                style: TextStyle(
                                    color: Colors.green, fontSize: 16)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: hangars.length,
                        itemBuilder: (context, i) {
                          final hangar = hangars[i];
                          final hangarItems = grouped[hangar]!;
                          final clientGroups =
                              _groupByClient(hangarItems);
                          final clientKeys = clientGroups.keys.toList()
                            ..sort();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    4, 12, 4, 6),
                                child: Row(children: [
                                  Icon(Icons.warehouse,
                                      size: 15, color: _teamColor),
                                  const SizedBox(width: 6),
                                  Text('Hangar $hangar',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: _teamColor,
                                          letterSpacing: 0.8)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _teamColor.withOpacity(0.1),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                        '${hangarItems.length}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: _teamColor)),
                                  ),
                                ]),
                              ),
                              ...clientKeys.map((key) {
                                final parts = key.split('|');
                                final local = parts[0];
                                final clientName =
                                    parts.length > 1 ? parts[1] : '';
                                final clientItems = clientGroups[key]!;
                                return _ClientSection(
                                  local: local,
                                  clientName: clientName,
                                  items: clientItems,
                                  isAwaiting: _isAwaiting,
                                  onConcluir: _markAwaiting,
                                  onCopy: _copyWhatsApp,
                                  teamColor: _teamColor,
                                );
                              }),
                            ],
                          );
                        },
                      ),
          ),
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
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      );
}

class _ClientSection extends StatelessWidget {
  final String local;
  final String clientName;
  final List<PendingItem> items;
  final bool Function(PendingItem) isAwaiting;
  final Future<void> Function(PendingItem) onConcluir;
  final void Function(PendingItem) onCopy;
  final Color teamColor;

  const _ClientSection({
    required this.local,
    required this.clientName,
    required this.items,
    required this.isAwaiting,
    required this.onConcluir,
    required this.onCopy,
    required this.teamColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Client header
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: teamColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: teamColor.withOpacity(0.3)),
                ),
                child: Text(
                  local.isEmpty ? '—' : local,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: teamColor),
                ),
              ),
              if (clientName.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(clientName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ],
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${items.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 10),
            ...items.map((item) => _ItemRow(
                  item: item,
                  awaiting: isAwaiting(item),
                  onConcluir: () => onConcluir(item),
                  onCopy: () => onCopy(item),
                )),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final PendingItem item;
  final bool awaiting;
  final VoidCallback onConcluir;
  final VoidCallback onCopy;

  const _ItemRow({
    required this.item,
    required this.awaiting,
    required this.onConcluir,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: awaiting ? Colors.blue.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: awaiting ? Colors.blue.shade200 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (awaiting)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: const [
                Icon(Icons.schedule, color: Colors.blue, size: 13),
                SizedBox(width: 4),
                Text('Aguardando validação',
                    style: TextStyle(
                        color: Colors.blue,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
          Text(item.description,
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(
                _fmt(item.createdAt),
                style:
                    const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 13),
              label: const Text('WhatsApp',
                  style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF25D366),
                side: const BorderSide(color: Color(0xFF25D366)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            if (!awaiting) ...[
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: onConcluir,
                icon: const Icon(Icons.check, size: 13),
                label: const Text('Concluir',
                    style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
