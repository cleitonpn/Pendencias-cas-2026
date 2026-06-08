import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/pending_item.dart';
import '../services/firestore_service.dart';

class ProducerHomeScreen extends StatefulWidget {
  final String producerName;
  const ProducerHomeScreen({super.key, required this.producerName});

  @override
  State<ProducerHomeScreen> createState() => _ProducerHomeScreenState();
}

class _ProducerHomeScreenState extends State<ProducerHomeScreen> {
  List<PendingItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items =
        await FirestoreService.getItemsByProducer(widget.producerName);
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  Map<String, Map<String, List<PendingItem>>> get _grouped {
    final result = <String, Map<String, List<PendingItem>>>{};
    for (final item in _items) {
      final h = item.hangar.isNotEmpty ? 'Hangar ${item.hangar}' : 'Sem Hangar';
      final c =
          '${item.local}${item.clientName.isNotEmpty ? " — ${item.clientName}" : ""}';
      result.putIfAbsent(h, () => {})[c] ??= [];
      result[h]![c]!.add(item);
    }
    return result;
  }

  String _buildWhatsAppText() {
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    final sb = StringBuffer();
    sb.writeln('*PENDÊNCIAS — ${widget.producerName}*');
    sb.writeln(date);

    final grouped = _grouped;
    final hangars = grouped.keys.toList()..sort();

    for (final hangar in hangars) {
      sb.writeln();
      sb.writeln('📍 *$hangar*');
      final clients = grouped[hangar]!;
      for (final clientKey in clients.keys) {
        sb.writeln();
        sb.writeln('*$clientKey*');
        for (final item in clients[clientKey]!) {
          sb.write('• ${item.team}');
          if (item.responsible.isNotEmpty) sb.write(' (${item.responsible})');
          sb.writeln(': ${item.description}');
        }
      }
    }

    return sb.toString().trim();
  }

  void _copyWhatsApp() {
    if (_items.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _buildWhatsAppText()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Lista copiada! Cole no WhatsApp.'),
      backgroundColor: Color(0xFF25D366),
      duration: Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Text(widget.producerName,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17)),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.white),
              tooltip: 'Copiar para WhatsApp',
              onPressed: _copyWhatsApp,
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Atualizar',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: Colors.green),
                      SizedBox(height: 12),
                      Text(
                        'Nenhuma pendência aberta!',
                        style: TextStyle(color: Colors.green, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : _PendingList(
                  grouped: _grouped,
                  totalItems: _items.length,
                  producerName: widget.producerName,
                  onCopy: _copyWhatsApp,
                ),
      floatingActionButton: _items.isNotEmpty && !_loading
          ? FloatingActionButton.extended(
              onPressed: _copyWhatsApp,
              backgroundColor: const Color(0xFF25D366),
              icon: const Icon(Icons.copy, color: Colors.white),
              label: const Text('Copiar para WhatsApp',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }
}

class _PendingList extends StatelessWidget {
  final Map<String, Map<String, List<PendingItem>>> grouped;
  final int totalItems;
  final String producerName;
  final VoidCallback onCopy;

  const _PendingList({
    required this.grouped,
    required this.totalItems,
    required this.producerName,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final hangars = grouped.keys.toList()..sort();

    return Column(
      children: [
        Container(
          color: Colors.orange.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$totalItems pendência${totalItems != 1 ? "s" : ""} abertas — $producerName',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: hangars.length,
            itemBuilder: (context, hi) {
              final hangar = hangars[hi];
              final clients = grouped[hangar]!;
              final clientKeys = clients.keys.toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A5F),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.warehouse,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(hangar,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                    ]),
                  ),
                  ...clientKeys.map((clientKey) {
                    final items = clients[clientKey]!;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8, left: 4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(clientKey,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            const Divider(height: 12),
                            ...items.map((item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _TeamDot(team: item.team),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.team +
                                                  (item.responsible.isNotEmpty
                                                      ? ' · ${item.responsible}'
                                                      : ''),
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12,
                                                  color:
                                                      Colors.grey.shade700),
                                            ),
                                            Text(item.description,
                                                style: const TextStyle(
                                                    fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TeamDot extends StatelessWidget {
  final String team;
  const _TeamDot({required this.team});

  Color get _color {
    switch (team.toLowerCase()) {
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
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(top: 3),
        decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
      );
}
