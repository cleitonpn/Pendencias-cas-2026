import 'package:flutter/material.dart';
import '../models/pending_item.dart';
import '../services/firestore_service.dart';
import 'producer_fair_clients_screen.dart';

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

  /// Groups items by fairName → returns map of fairName → list of items
  Map<String, List<PendingItem>> get _byFair {
    final result = <String, List<PendingItem>>{};
    for (final item in _items) {
      final fair = item.fairName.isNotEmpty ? item.fairName : 'Sem Feira';
      result.putIfAbsent(fair, () => []).add(item);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final byFair = _byFair;
    final fairNames = byFair.keys.toList()..sort();

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
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: fairNames.length,
                  itemBuilder: (context, index) {
                    final fairName = fairNames[index];
                    final items = byFair[fairName]!;
                    final openCount =
                        items.where((i) => !i.awaitingValidation).length;
                    final awaitingCount =
                        items.where((i) => i.awaitingValidation).length;

                    return _FairCard(
                      fairName: fairName,
                      openCount: openCount,
                      awaitingCount: awaitingCount,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProducerFairClientsScreen(
                            producerName: widget.producerName,
                            fairName: fairName,
                            items: items,
                          ),
                        ),
                      ).then((_) => _load()),
                    );
                  },
                ),
    );
  }
}

class _FairCard extends StatelessWidget {
  final String fairName;
  final int openCount;
  final int awaitingCount;
  final VoidCallback onTap;

  const _FairCard({
    required this.fairName,
    required this.openCount,
    required this.awaitingCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.festival,
                    color: Color(0xFF1E3A5F), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fairName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF1E3A5F))),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, children: [
                      if (openCount > 0)
                        _Badge(
                          label: '$openCount aberta${openCount != 1 ? "s" : ""}',
                          color: Colors.orange,
                        ),
                      if (awaitingCount > 0)
                        _Badge(
                          label:
                              '$awaitingCount aguardando',
                          color: Colors.blue,
                        ),
                    ]),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      );
}
