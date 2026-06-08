import 'package:flutter/material.dart';
import '../models/pending_item.dart';
import 'producer_client_detail_screen.dart';

class ProducerFairClientsScreen extends StatelessWidget {
  final String producerName;
  final String fairName;
  final List<PendingItem> items;

  const ProducerFairClientsScreen({
    super.key,
    required this.producerName,
    required this.fairName,
    required this.items,
  });

  /// Groups items by (hangar, clientName+local) and returns
  /// a map: hangar → list of client entries.
  Map<String, List<_ClientEntry>> get _grouped {
    final result = <String, List<_ClientEntry>>{};
    final clientMap = <String, _ClientEntry>{};

    for (final item in items) {
      final hangar = item.hangar.isNotEmpty ? item.hangar : 'Sem Hangar';
      final key = '${item.local}__${item.clientName}';
      if (!clientMap.containsKey(key)) {
        clientMap[key] = _ClientEntry(
          local: item.local,
          clientName: item.clientName,
          hangar: item.hangar,
          items: [],
        );
        result.putIfAbsent(hangar, () => []).add(clientMap[key]!);
      }
      clientMap[key]!.items.add(item);
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final hangars = grouped.keys.toList()..sort();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Text(fairName,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: hangars.length,
        itemBuilder: (context, hi) {
          final hangar = hangars[hi];
          final clients = grouped[hangar]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.warehouse, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    hangar.isNotEmpty
                        ? 'Hangar $hangar'
                        : 'Sem Hangar',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ]),
              ),
              ...clients.map((entry) {
                final openCount =
                    entry.items.where((i) => !i.awaitingValidation).length;
                final awaitingCount =
                    entry.items.where((i) => i.awaitingValidation).length;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8, left: 4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProducerClientDetailScreen(
                          producerName: producerName,
                          clientName: entry.clientName,
                          local: entry.local,
                          hangar: entry.hangar,
                          items: entry.items,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (entry.local.isNotEmpty)
                                  Text('Stand ${entry.local}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey)),
                                Text(
                                  entry.clientName.isNotEmpty
                                      ? entry.clientName
                                      : 'Stand ${entry.local}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (openCount > 0) ...[
                            _CountBadge(count: openCount, color: Colors.orange),
                            const SizedBox(width: 6),
                          ],
                          if (awaitingCount > 0)
                            _CountBadge(count: awaitingCount, color: Colors.blue),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _ClientEntry {
  final String local;
  final String clientName;
  final String hangar;
  final List<PendingItem> items;

  _ClientEntry({
    required this.local,
    required this.clientName,
    required this.hangar,
    required this.items,
  });
}

class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;
  const _CountBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '$count',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold),
          ),
        ),
      );
}
