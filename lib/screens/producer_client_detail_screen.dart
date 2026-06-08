import 'package:flutter/material.dart';
import '../models/pending_item.dart';
import '../services/firestore_service.dart';

class ProducerClientDetailScreen extends StatefulWidget {
  final String producerName;
  final String clientName;
  final String local;
  final String hangar;
  final List<PendingItem> items;

  const ProducerClientDetailScreen({
    super.key,
    required this.producerName,
    required this.clientName,
    required this.local,
    required this.hangar,
    required this.items,
  });

  @override
  State<ProducerClientDetailScreen> createState() =>
      _ProducerClientDetailScreenState();
}

class _ProducerClientDetailScreenState
    extends State<ProducerClientDetailScreen> {
  late List<PendingItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
  }

  Future<void> _markAwaiting(PendingItem item) async {
    if (item.firestoreId == null) return;
    try {
      await FirestoreService.markAwaitingValidation(item.firestoreId!);
      if (mounted) {
        setState(() {
          final idx = _items.indexWhere(
              (i) => i.firestoreId == item.firestoreId);
          if (idx >= 0) {
            final old = _items[idx];
            _items[idx] = PendingItem(
              id: old.id,
              firestoreId: old.firestoreId,
              clientId: old.clientId,
              clientName: old.clientName,
              producerName: old.producerName,
              fairName: old.fairName,
              local: old.local,
              hangar: old.hangar,
              team: old.team,
              responsible: old.responsible,
              description: old.description,
              isResolved: old.isResolved,
              awaitingValidation: true,
              createdAt: old.createdAt,
              resolvedAt: old.resolvedAt,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao marcar pendência: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.local.isNotEmpty
        ? 'Stand ${widget.local}'
        : widget.clientName;

    final openItems =
        _items.where((i) => !i.awaitingValidation).toList();
    final awaitingItems =
        _items.where((i) => i.awaitingValidation).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17)),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Client name header card
            Container(
              width: double.infinity,
              color: const Color(0xFF1E3A5F),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.clientName.isNotEmpty
                        ? widget.clientName
                        : 'Stand ${widget.local}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  if (widget.hangar.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Hangar ${widget.hangar}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Open items
            if (openItems.isNotEmpty) ...[
              _SectionTitle(
                  text: 'PENDÊNCIAS ABERTAS (${openItems.length})',
                  color: Colors.orange),
              ...openItems.map((item) => _ProducerItemCard(
                    item: item,
                    onConcluir: () => _markAwaiting(item),
                  )),
            ],

            // Awaiting validation items
            if (awaitingItems.isNotEmpty) ...[
              _SectionTitle(
                  text: 'AGUARDANDO VALIDAÇÃO (${awaitingItems.length})',
                  color: Colors.blue),
              ...awaitingItems.map((item) => _ProducerItemCard(
                    item: item,
                    onConcluir: null,
                  )),
            ],

            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: Text('Nenhuma pendência.',
                        style: TextStyle(color: Colors.grey))),
              ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionTitle({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
                letterSpacing: 1)),
      );
}

class _ProducerItemCard extends StatelessWidget {
  final PendingItem item;
  final VoidCallback? onConcluir;

  const _ProducerItemCard({required this.item, this.onConcluir});

  Color get _teamColor {
    switch (item.team.toLowerCase()) {
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
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAwaiting = item.awaitingValidation;
    final cardColor = isAwaiting ? Colors.blue.shade50 : Colors.white;
    final borderColor =
        isAwaiting ? Colors.blue.shade200 : Colors.orange.shade200;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              // Team badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _teamColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _teamColor.withOpacity(0.4)),
                ),
                child: Text(item.team,
                    style: TextStyle(
                        color: _teamColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
              if (item.responsible.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(item.responsible,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
              const Spacer(),
              if (isAwaiting)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Aguardando validação do admin',
                      style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
            ]),
            const SizedBox(height: 8),
            Text(item.description, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 6),
            Text(
              _fmt(item.createdAt),
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
            if (!isAwaiting && onConcluir != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onConcluir,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Concluir'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
