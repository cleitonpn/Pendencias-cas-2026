import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/client.dart';
import '../services/database_service.dart';
import 'producer_client_detail_screen.dart';

class ProducerClientListScreen extends StatefulWidget {
  final String hangar;
  final String producerName;

  const ProducerClientListScreen({
    super.key,
    required this.hangar,
    required this.producerName,
  });

  @override
  State<ProducerClientListScreen> createState() =>
      _ProducerClientListScreenState();
}

class _ProducerClientListScreenState
    extends State<ProducerClientListScreen> {
  String _search = '';
  bool _filterPending = false;
  Map<String, int> _pendingCounts = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCounts());
  }

  Future<void> _loadCounts() async {
    final clients = _allClients;
    if (clients.isEmpty) return;
    final counts = await DatabaseService.getPendingCounts(
        clients.map((c) => c.rowId).toList());
    if (mounted) setState(() => _pendingCounts = counts);
  }

  // All clients for this producer+hangar (search applied, pending filter NOT applied).
  List<Client> get _allClients {
    final all = context.read<AppProvider>().clients;
    var list = all.where((c) {
      if (c.produtor != widget.producerName) return false;
      final h = c.hangar.isEmpty ? 'Todos os Stands' : c.hangar;
      return h == widget.hangar;
    }).toList()
      ..sort((a, b) => a.local.compareTo(b.local));

    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((c) =>
              c.nome.toLowerCase().contains(q) ||
              c.local.contains(q) ||
              c.montagem.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  // Clients shown in the list (pending filter applied on top of _allClients).
  List<Client> get _displayedClients {
    final list = _allClients;
    if (!_filterPending) return list;
    return list.where((c) => (_pendingCounts[c.rowId] ?? 0) > 0).toList();
  }

  @override
  Widget build(BuildContext context) {
    final all = _allClients;
    final displayed = _displayedClients;
    final withPending = all.where((c) => (_pendingCounts[c.rowId] ?? 0) > 0).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Text(
            widget.hangar == 'Todos os Stands'
                ? 'Todos os Stands'
                : 'Hangar ${widget.hangar}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar stand ou cliente...',
                hintStyle:
                    TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixIcon: Icon(Icons.search,
                    color: Colors.white.withOpacity(0.6)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Stats / filter bar
          Container(
            color: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _StatChip(
                  label: 'Total',
                  value: all.length,
                  color: Colors.blue,
                  selected: !_filterPending,
                  onTap: () => setState(() => _filterPending = false),
                ),
                const SizedBox(width: 8),
                _StatChip(
                  label: 'Com pendência',
                  value: withPending,
                  color: Colors.orange,
                  selected: _filterPending,
                  onTap: () => setState(() => _filterPending = !_filterPending),
                ),
              ],
            ),
          ),
          Expanded(
            child: displayed.isEmpty
                ? Center(
                    child: Text(
                      _filterPending
                          ? 'Nenhum cliente com pendência.'
                          : 'Nenhum cliente encontrado.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: displayed.length,
                    itemBuilder: (context, i) => _ClientCard(
                      client: displayed[i],
                      pendingCount:
                          _pendingCounts[displayed[i].rowId] ?? 0,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProducerClientDetailScreen(
                              client: displayed[i],
                              producerName: widget.producerName,
                            ),
                          ),
                        );
                        await _loadCounts();
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? color : color.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : color,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  final Client client;
  final int pendingCount;
  final VoidCallback onTap;

  const _ClientCard({
    required this.client,
    required this.pendingCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    client.local.isEmpty ? '—' : client.local,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E3A5F)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client.displayName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    if (client.montagem.isNotEmpty)
                      Text(client.montagem,
                          style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12)),
                    if (client.area.isNotEmpty)
                      Text('${client.area} m²',
                          style: const TextStyle(
                              color: Color(0xFF1E3A5F),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (pendingCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$pendingCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
