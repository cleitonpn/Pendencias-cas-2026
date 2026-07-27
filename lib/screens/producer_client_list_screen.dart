import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/client.dart';
import '../models/pending_item.dart';
import '../services/database_service.dart';
import 'producer_client_detail_screen.dart';
import 'producer_pending_screen.dart' show teamColor;

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

/// Ordenação da lista de stands.
enum _ClientSort { stand, antigas, recentes }

class _ProducerClientListScreenState
    extends State<ProducerClientListScreen> {
  String _search = '';
  bool _filterPending = false;

  /// Pendências abertas do produtor nesta feira. Antes a tela só carregava a
  /// contagem por cliente; filtrar por equipe e ordenar por data exige os
  /// itens em si.
  List<PendingItem> _items = [];

  /// Equipes marcadas. Vazio = todas.
  final Set<String> _teamFilter = {};
  _ClientSort _sort = _ClientSort.stand;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCounts());
  }

  Future<void> _loadCounts() async {
    final fairId = context.read<AppProvider>().currentFair?.id;
    if (fairId == null) return;
    final items = await DatabaseService.getPendingItemsByProdutor(
        widget.producerName,
        fairId: fairId);
    if (!mounted) return;
    setState(() {
      _items = items;
      final present = items.map(_teamKey).toSet();
      _teamFilter.removeWhere((t) => !present.contains(t));
    });
  }

  static String _teamKey(PendingItem i) =>
      i.team.isEmpty ? 'Sem equipe' : i.team;

  /// Pendências por cliente, já com o filtro de equipe aplicado.
  Map<String, List<PendingItem>> get _itemsByClient {
    final map = <String, List<PendingItem>>{};
    for (final it in _items) {
      if (_teamFilter.isNotEmpty && !_teamFilter.contains(_teamKey(it))) {
        continue;
      }
      map.putIfAbsent(it.clientId, () => []).add(it);
    }
    return map;
  }

  /// Equipes presentes nas pendências deste produtor, com contagem.
  Map<String, int> get _teamCounts {
    final counts = <String, int>{};
    for (final it in _items) {
      final t = _teamKey(it);
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return Map.fromEntries(
        counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  int _countFor(Client c) => _itemsByClient[c.rowId]?.length ?? 0;

  DateTime? _oldestFor(Client c) {
    final list = _itemsByClient[c.rowId];
    if (list == null || list.isEmpty) return null;
    return list
        .map((i) => i.createdAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  DateTime? _newestFor(Client c) {
    final list = _itemsByClient[c.rowId];
    if (list == null || list.isEmpty) return null;
    return list
        .map((i) => i.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
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

  // Clients shown in the list (pending/team filters + sort applied).
  List<Client> get _displayedClients {
    var list = _allClients;

    // Com filtro de equipe ativo, stands sem pendência daquela equipe saem da
    // lista — é o que torna o filtro útil em campo.
    if (_filterPending || _teamFilter.isNotEmpty) {
      list = list.where((c) => _countFor(c) > 0).toList();
    }

    if (_sort != _ClientSort.stand) {
      final oldestFirst = _sort == _ClientSort.antigas;
      list = List<Client>.from(list)
        ..sort((a, b) {
          final da = oldestFirst ? _oldestFor(a) : _newestFor(a);
          final db = oldestFirst ? _oldestFor(b) : _newestFor(b);
          // Stands sem pendência não têm data: vão para o fim.
          if (da == null && db == null) return a.local.compareTo(b.local);
          if (da == null) return 1;
          if (db == null) return -1;
          return oldestFirst ? da.compareTo(db) : db.compareTo(da);
        });
    }
    return list;
  }

  Widget _chip({
    required String label,
    int? count,
    IconData? icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: selected ? color : color.withOpacity(0.32)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: selected ? Colors.white : color),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : color)),
            if (count != null) ...[
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withOpacity(0.25)
                      : color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$count',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: selected ? Colors.white : color)),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _filtersBar() {
    final counts = _teamCounts;
    const navy = Color(0xFF1E3A5F);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (counts.length >= 2) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 6, left: 2),
              child: Text('EQUIPE',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1)),
            ),
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip(
                    label: 'Todas',
                    count: _items.length,
                    color: navy,
                    selected: _teamFilter.isEmpty,
                    onTap: () => setState(_teamFilter.clear),
                  ),
                  ...counts.entries.map((e) => _chip(
                        label: e.key,
                        count: e.value,
                        color: teamColor(e.key),
                        selected: _teamFilter.contains(e.key),
                        onTap: () => setState(() {
                          if (!_teamFilter.remove(e.key)) {
                            _teamFilter.add(e.key);
                          }
                        }),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          const Padding(
            padding: EdgeInsets.only(bottom: 6, left: 2),
            child: Text('ORDENAR',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
          ),
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chip(
                  label: 'Stand',
                  icon: Icons.tag,
                  color: navy,
                  selected: _sort == _ClientSort.stand,
                  onTap: () => setState(() => _sort = _ClientSort.stand),
                ),
                _chip(
                  label: 'Mais antigas',
                  icon: Icons.arrow_upward,
                  color: navy,
                  selected: _sort == _ClientSort.antigas,
                  onTap: () => setState(() => _sort = _ClientSort.antigas),
                ),
                _chip(
                  label: 'Mais recentes',
                  icon: Icons.arrow_downward,
                  color: navy,
                  selected: _sort == _ClientSort.recentes,
                  onTap: () => setState(() => _sort = _ClientSort.recentes),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _allClients;
    final displayed = _displayedClients;
    final withPending = all.where((c) => _countFor(c) > 0).length;

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
          if (_items.isNotEmpty) _filtersBar(),
          Expanded(
            child: displayed.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _teamFilter.isNotEmpty
                                ? 'Nenhum stand com pendência\nda equipe selecionada.'
                                : _filterPending
                                    ? 'Nenhum cliente com pendência.'
                                    : 'Nenhum cliente encontrado.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          if (_teamFilter.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => setState(_teamFilter.clear),
                              icon: const Icon(Icons.clear_all, size: 18),
                              label: const Text('Mostrar todas'),
                            ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: displayed.length,
                    itemBuilder: (context, i) => _ClientCard(
                      client: displayed[i],
                      pendingCount: _countFor(displayed[i]),
                      oldestAt: _oldestFor(displayed[i]),
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
  final DateTime? oldestAt;
  final VoidCallback onTap;

  const _ClientCard({
    required this.client,
    required this.pendingCount,
    required this.oldestAt,
    required this.onTap,
  });

  static String _age(DateTime d) {
    final days = DateTime.now().difference(d).inDays;
    if (days <= 0) return 'hoje';
    if (days == 1) return 'há 1 dia';
    return 'há $days dias';
  }

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
                    if (oldestAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(children: [
                          Icon(Icons.schedule,
                              size: 12,
                              color: DateTime.now()
                                          .difference(oldestAt!)
                                          .inDays >=
                                      2
                                  ? Colors.red.shade700
                                  : Colors.grey),
                          const SizedBox(width: 3),
                          Text(
                            'mais antiga ${_age(oldestAt!)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: DateTime.now()
                                          .difference(oldestAt!)
                                          .inDays >=
                                      2
                                  ? Colors.red.shade700
                                  : Colors.grey,
                            ),
                          ),
                        ]),
                      ),
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
