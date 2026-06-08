import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/pending_item.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';

class ProducerPendingScreen extends StatefulWidget {
  final String? lockedProducer;
  final bool canResolve;

  const ProducerPendingScreen({
    super.key,
    this.lockedProducer,
    this.canResolve = false,
  });

  @override
  State<ProducerPendingScreen> createState() => _ProducerPendingScreenState();
}

class _ProducerPendingScreenState extends State<ProducerPendingScreen> {
  List<String> _producers = [];
  String? _selected;
  List<PendingItem> _items = [];
  bool _loading = false;
  late int _fairId;

  @override
  void initState() {
    super.initState();
    _fairId = context.read<AppProvider>().currentFair?.id ?? 1;
    _loadProducers();
    if (widget.lockedProducer != null) {
      _selectProducer(widget.lockedProducer!);
    }
  }

  Future<void> _loadProducers() async {
    final producers = await DatabaseService.getProducers(fairId: _fairId);
    if (mounted) setState(() => _producers = producers);
  }

  Future<void> _selectProducer(String produtor) async {
    setState(() {
      _selected = produtor;
      _loading = true;
    });
    final items =
        await DatabaseService.getPendingItemsByProdutor(produtor, fairId: _fairId);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _resolveItem(PendingItem item) async {
    await DatabaseService.resolvePendingItem(item.id!);
    if (_selected != null) await _selectProducer(_selected!);
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
    final fairName = context.read<AppProvider>().currentFairName;
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    final sb = StringBuffer();
    sb.writeln('*PENDÊNCIAS — $_selected*');
    sb.writeln('$fairName | $date');

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
    final text = _buildWhatsAppText();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Lista copiada! Cole no WhatsApp.'),
      backgroundColor: Color(0xFF25D366),
      duration: Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = widget.lockedProducer != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Text(
            isLocked
                ? widget.lockedProducer!
                : 'Pendências por Produtor',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17)),
        actions: [
          if (_selected != null && _items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.white),
              tooltip: 'Copiar para WhatsApp',
              onPressed: _copyWhatsApp,
            ),
        ],
      ),
      body: Column(
        children: [
          // Producer selector — hidden when locked
          if (!isLocked)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SELECIONE O PRODUTOR',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 1)),
                  const SizedBox(height: 10),
                  _producers.isEmpty
                      ? const Text(
                          'Nenhum produtor encontrado.\nSincronize a planilha primeiro.',
                          style: TextStyle(color: Colors.grey))
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _producers.map((p) {
                            final sel = _selected == p;
                            return GestureDetector(
                              onTap: () => _selectProducer(p),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? const Color(0xFF1E3A5F)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: sel
                                        ? const Color(0xFF1E3A5F)
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Text(
                                  p,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: sel
                                        ? Colors.white
                                        : Colors.black87,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ],
              ),
            ),

          Expanded(
            child: _selected == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_search,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('Selecione um produtor acima',
                            style:
                                TextStyle(color: Colors.grey, fontSize: 16)),
                      ],
                    ),
                  )
                : _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_outline,
                                    size: 64, color: Colors.green),
                                const SizedBox(height: 12),
                                Text(
                                  'Nenhuma pendência aberta\npara $_selected!',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.green, fontSize: 16),
                                ),
                              ],
                            ),
                          )
                        : _PendingList(
                            grouped: _grouped,
                            totalItems: _items.length,
                            produtor: _selected!,
                            canResolve: widget.canResolve,
                            onCopy: _copyWhatsApp,
                            onResolve: _resolveItem,
                          ),
          ),
        ],
      ),
      floatingActionButton:
          (_selected != null && _items.isNotEmpty && !_loading)
              ? FloatingActionButton.extended(
                  onPressed: _copyWhatsApp,
                  backgroundColor: const Color(0xFF25D366),
                  icon: const Icon(Icons.copy, color: Colors.white),
                  label: const Text('Copiar para WhatsApp',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                )
              : null,
    );
  }
}

class _PendingList extends StatelessWidget {
  final Map<String, Map<String, List<PendingItem>>> grouped;
  final int totalItems;
  final String produtor;
  final bool canResolve;
  final VoidCallback onCopy;
  final Future<void> Function(PendingItem) onResolve;

  const _PendingList({
    required this.grouped,
    required this.totalItems,
    required this.produtor,
    required this.canResolve,
    required this.onCopy,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final hangars = grouped.keys.toList()..sort();

    return Column(
      children: [
        Container(
          color: Colors.orange.shade50,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.warning_amber,
                  color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$totalItems pendência${totalItems != 1 ? "s" : ""} abertas — $produtor',
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
                      margin:
                          const EdgeInsets.only(bottom: 8, left: 4),
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
                                  padding:
                                      const EdgeInsets.only(bottom: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _TeamDot(team: item.team),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment
                                                      .start,
                                              children: [
                                                Text(
                                                  item.team +
                                                      (item.responsible
                                                              .isNotEmpty
                                                          ? ' · ${item.responsible}'
                                                          : ''),
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 12,
                                                      color: Colors
                                                          .grey.shade700),
                                                ),
                                                Text(item.description,
                                                    style: const TextStyle(
                                                        fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (canResolve) ...[
                                        const SizedBox(height: 6),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: ElevatedButton.icon(
                                            onPressed: () =>
                                                onResolve(item),
                                            icon: const Icon(Icons.check,
                                                size: 14),
                                            label: const Text('Resolver',
                                                style: TextStyle(
                                                    fontSize: 12)),
                                            style:
                                                ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.green,
                                              foregroundColor:
                                                  Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6),
                                              minimumSize: Size.zero,
                                            ),
                                          ),
                                        ),
                                      ],
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
