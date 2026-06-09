import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/pending_item.dart';
import '../services/database_service.dart';
import 'client_detail_screen.dart';

/// Fair-wide list of every pending item, with a status filter and search.
/// Lets the admin/producer see and jump to any pending without drilling
/// through hangar → stand.
class PendingBoardScreen extends StatefulWidget {
  const PendingBoardScreen({super.key});

  @override
  State<PendingBoardScreen> createState() => _PendingBoardScreenState();
}

enum _Filter { todas, pendentes, aguardando, resolvidas }

class _PendingBoardScreenState extends State<PendingBoardScreen> {
  List<PendingItem> _all = [];
  bool _loading = true;
  String _search = '';
  _Filter _filter = _Filter.pendentes;
  AppProvider? _provider;

  @override
  void initState() {
    super.initState();
    _load();
    _provider = context.read<AppProvider>();
    _provider!.addListener(_onChanged);
  }

  @override
  void dispose() {
    _provider?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    final fair = context.read<AppProvider>().currentFair;
    if (fair?.id == null) return;
    if (!silent) setState(() => _loading = true);
    final items =
        await DatabaseService.getAllPendingItems(fairId: fair!.id!);
    if (mounted) {
      setState(() {
        _all = items;
        _loading = false;
      });
    }
  }

  bool _matchesFilter(PendingItem p) {
    switch (_filter) {
      case _Filter.todas:
        return true;
      case _Filter.pendentes:
        return !p.isResolved && !p.awaitingValidation;
      case _Filter.aguardando:
        return !p.isResolved && p.awaitingValidation;
      case _Filter.resolvidas:
        return p.isResolved;
    }
  }

  bool _matchesSearch(PendingItem p) {
    if (_search.isEmpty) return true;
    final q = _search.toLowerCase();
    return p.clientName.toLowerCase().contains(q) ||
        p.local.toLowerCase().contains(q) ||
        p.team.toLowerCase().contains(q) ||
        p.description.toLowerCase().contains(q);
  }

  int _countFor(_Filter f) {
    return _all.where((p) {
      switch (f) {
        case _Filter.todas:
          return true;
        case _Filter.pendentes:
          return !p.isResolved && !p.awaitingValidation;
        case _Filter.aguardando:
          return !p.isResolved && p.awaitingValidation;
        case _Filter.resolvidas:
          return p.isResolved;
      }
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final items = _all.where(_matchesFilter).where(_matchesSearch).toList()
      ..sort((a, b) {
        final h = a.hangar.compareTo(b.hangar);
        if (h != 0) return h;
        return a.local.compareTo(b.local);
      });

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Pendências',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar cliente, stand, equipe ou descrição...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixIcon:
                    Icon(Icons.search, color: Colors.white.withOpacity(0.6)),
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
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _filterChip('Pendentes', _Filter.pendentes, Colors.deepOrange),
                _filterChip('Aguardando', _Filter.aguardando, Colors.amber.shade800),
                _filterChip('Resolvidas', _Filter.resolvidas, Colors.green),
                _filterChip('Todas', _Filter.todas, const Color(0xFF1E3A5F)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? const Center(
                        child: Text('Nenhuma pendência neste filtro.',
                            style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: items.length,
                        itemBuilder: (context, i) =>
                            _BoardCard(item: items[i], onTap: () => _open(items[i])),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(PendingItem item) async {
    final client = context.read<AppProvider>().clientById(item.clientId);
    if (client == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cliente não encontrado. Sincronize a planilha.')));
      return;
    }
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ClientDetailScreen(client: client)));
    await _load(silent: true);
  }

  Widget _filterChip(String label, _Filter f, Color color) {
    final sel = _filter == f;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label (${_countFor(f)})'),
        selected: sel,
        onSelected: (_) => setState(() => _filter = f),
        selectedColor: color,
        labelStyle: TextStyle(
            color: sel ? Colors.white : color,
            fontWeight: FontWeight.w600,
            fontSize: 12),
        backgroundColor: color.withOpacity(0.08),
        side: BorderSide(color: color.withOpacity(0.4)),
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  final PendingItem item;
  final VoidCallback onTap;
  const _BoardCard({required this.item, required this.onTap});

  Color get _statusColor {
    if (item.isResolved) return Colors.green;
    if (item.awaitingValidation) return Colors.amber;
    return Colors.deepOrange;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: _statusColor, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(item.clientName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      Text(
                          item.hangar.isNotEmpty
                              ? 'H${item.hangar} • ${item.local}'
                              : item.local,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(item.team,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E3A5F))),
                      if (item.fromClient) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.storefront,
                            size: 13, color: Colors.orange),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 13, color: Colors.black87)),
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
