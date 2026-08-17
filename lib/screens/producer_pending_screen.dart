import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/pending_item.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../services/actor.dart';
import '../widgets/furniture_pick_chips.dart';

class ProducerPendingScreen extends StatefulWidget {
  final String? lockedProducer;
  final bool canResolve;

  /// Quando informado, restringe a lista a esta feira. A consulta ao Firestore
  /// busca por produtor sem filtrar feira, então abrir a tela de dentro de uma
  /// feira sem isto misturaria pendências de outras.
  final String? fairName;

  const ProducerPendingScreen({
    super.key,
    this.lockedProducer,
    this.canResolve = false,
    this.fairName,
  });

  @override
  State<ProducerPendingScreen> createState() => _ProducerPendingScreenState();
}

/// Ordenação da lista. `hangar` mantém o agrupamento por hangar → cliente;
/// as opções por data viram uma lista corrida, que é a única forma da ordem
/// cronológica ficar legível.
enum _Sort { hangar, antigas, recentes }

class _ProducerPendingScreenState extends State<ProducerPendingScreen> {
  List<String> _producers = [];
  String? _selected;
  List<PendingItem> _items = [];
  bool _loading = false;
  int? _fairId;

  /// Equipes marcadas no filtro. Vazio = mostra todas.
  final Set<String> _teamFilter = {};

  _Sort _sort = _Sort.hangar;

  bool get _isProducerMode => widget.lockedProducer != null;

  @override
  void initState() {
    super.initState();
    _fairId = context.read<AppProvider>().currentFair?.id;
    if (_isProducerMode) {
      _selectProducer(widget.lockedProducer!);
    } else {
      _loadProducers();
    }
  }

  Future<void> _loadProducers() async {
    if (_fairId == null) return;
    final producers = await DatabaseService.getProducers(fairId: _fairId!);
    if (mounted) setState(() => _producers = producers);
  }

  Future<void> _selectProducer(String produtor) async {
    // Trocar de produtor zera o filtro; recarregar a lista não (ver _reload).
    setState(() => _teamFilter.clear());
    await _loadItems(produtor);
  }

  /// Recarrega mantendo o filtro de equipe — usado após concluir uma pendência,
  /// senão o produtor perderia o filtro a cada item concluído em campo.
  Future<void> _reload() async {
    if (_selected != null) await _loadItems(_selected!);
  }

  Future<void> _loadItems(String produtor) async {
    setState(() { _selected = produtor; _loading = true; });

    List<PendingItem> items;
    if (_isProducerMode) {
      // Producer mode: read from Firestore
      items = await FirestoreService.getItemsByProducer(produtor);
      final fair = widget.fairName;
      if (fair != null && fair.isNotEmpty) {
        // Itens antigos podem não ter fairName gravado; mantê-los é melhor do
        // que sumir com trabalho real da lista de campo.
        items = items
            .where((i) => i.fairName == fair || i.fairName.isEmpty)
            .toList();
      }
    } else {
      // Admin mode: read from local SQLite
      items = _fairId != null
          ? await DatabaseService.getPendingItemsByProdutor(produtor,
              fairId: _fairId!)
          : [];
    }

    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
      // Descarta equipes que deixaram de existir na lista, senão o filtro
      // continuaria apontando para uma equipe já zerada.
      final present = items.map(_teamKey).toSet();
      _teamFilter.removeWhere((t) => !present.contains(t));
    });
  }

  Future<void> _resolveItem(PendingItem item) async {
    // Nome real de quem está concluindo. O texto fixo "Administrador"
    // creditava todo o trabalho a um usuário que não existe.
    final by = _isProducerMode
        ? (_selected ?? 'Produtor')
        : (Actor.name.isEmpty ? 'Administrador' : Actor.name);
    if (_isProducerMode) {
      // Producer mode: resolve in Firestore only
      if (item.firestoreId == null) return;
      await FirestoreService.resolveItem(item.firestoreId!, resolvedBy: by);
    } else {
      // Admin mode: resolve in both SQLite and Firestore
      if (item.id != null) {
        await context
            .read<AppProvider>()
            .resolveItem(item.id!, firestoreId: item.firestoreId, by: by);
      }
    }
    await _reload();
  }

  /// Rótulo da equipe usado tanto nos chips quanto no filtro — sem isto, um
  /// item com equipe vazia apareceria como "Sem equipe" no chip mas nunca
  /// casaria com o filtro.
  static String _teamKey(PendingItem i) =>
      i.team.isEmpty ? 'Sem equipe' : i.team;

  /// Pendências após o filtro de equipe (vazio = todas).
  List<PendingItem> get _visible => _teamFilter.isEmpty
      ? _items
      : _items.where((i) => _teamFilter.contains(_teamKey(i))).toList();

  /// Lista corrida em ordem cronológica, usada nos modos por data.
  List<PendingItem> get _byDate {
    final list = List<PendingItem>.from(_visible);
    list.sort((a, b) => _sort == _Sort.antigas
        ? a.createdAt.compareTo(b.createdAt)
        : b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Equipes presentes nas pendências deste produtor, com a contagem de cada
  /// uma — o produtor vê de cara onde está o volume de trabalho.
  Map<String, int> get _teamCounts {
    final counts = <String, int>{};
    for (final item in _items) {
      final t = _teamKey(item);
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return Map.fromEntries(
        counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  Map<String, Map<String, List<PendingItem>>> get _grouped {
    final result = <String, Map<String, List<PendingItem>>>{};
    for (final item in _visible) {
      final h = item.hangar.isNotEmpty ? 'Hangar ${item.hangar}' : 'Sem Hangar';
      final c =
          '${item.local}${item.clientName.isNotEmpty ? " — ${item.clientName}" : ""}';
      result.putIfAbsent(h, () => {})[c] ??= [];
      result[h]![c]!.add(item);
    }
    return result;
  }

  String _buildWhatsAppText() {
    final fairName = _isProducerMode
        ? (_items.isNotEmpty
            ? (_items.first as dynamic).fairName ?? 'Montagem USET'
            : 'Montagem USET')
        : context.read<AppProvider>().currentFairName;

    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    final sb = StringBuffer();
    sb.writeln('*PENDÊNCIAS — $_selected*');
    sb.writeln('$fairName | $date');
    // Deixa explícito que a lista está filtrada, senão quem recebe no
    // WhatsApp acha que são todas as pendências do produtor.
    if (_teamFilter.isNotEmpty) {
      final teams = _teamFilter.toList()..sort();
      sb.writeln('_Equipe: ${teams.join(", ")}_');
    }

    // Nos modos por data a mensagem sai na mesma ordem que está na tela,
    // senão o produtor copia uma lista diferente da que está vendo.
    if (_sort != _Sort.hangar) {
      sb.writeln(_sort == _Sort.antigas
          ? '_Mais antigas primeiro_'
          : '_Mais recentes primeiro_');
      for (final item in _byDate) {
        final d = item.createdAt;
        final dd = '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}';
        sb.writeln();
        sb.writeln('*${item.local.isNotEmpty ? "Stand ${item.local}" : "Sem stand"}'
            '${item.clientName.isNotEmpty ? " — ${item.clientName}" : ""}* ($dd)');
        sb.write('• ${item.team}');
        if (item.responsible.isNotEmpty) sb.write(' (${item.responsible})');
        // O móvel marcado vai junto: é o relatório que a equipe lê no
        // WhatsApp, e sem o item ela chega no stand sem saber o que levar.
        if (item.furnitureItems.isNotEmpty) {
          sb.write(' [${item.furnitureLabel}]');
        }
        sb.writeln(': ${item.description}');
      }
      return sb.toString().trim();
    }

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
          if (item.furnitureItems.isNotEmpty) {
            sb.write(' [${item.furnitureLabel}]');
          }
          sb.writeln(': ${item.description}');
        }
      }
    }

    return sb.toString().trim();
  }

  void _copyWhatsApp() {
    if (_visible.isEmpty) return;
    final text = _buildWhatsAppText();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Lista copiada! Cole no WhatsApp.'),
      backgroundColor: Color(0xFF25D366),
      duration: Duration(seconds: 3),
    ));
  }

  /// Barra de filtro por equipe: um chip por equipe presente nas pendências,
  /// com a contagem. Toca para alternar; nada marcado = todas.
  Widget _teamFilterBar() {
    final counts = _teamCounts;
    final showTeams = counts.length >= 2; // com 1 equipe só, filtrar não ajuda

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTeams) ...[
            Row(children: [
              const Icon(Icons.groups, size: 15, color: Colors.grey),
              const SizedBox(width: 5),
              const Text('FILTRAR POR EQUIPE',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1)),
              const Spacer(),
              if (_teamFilter.isNotEmpty)
                Text('${_visible.length} de ${_items.length}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _teamChip(
                    label: 'Todas',
                    count: _items.length,
                    color: const Color(0xFF1E3A5F),
                    selected: _teamFilter.isEmpty,
                    onTap: () => setState(_teamFilter.clear),
                  ),
                  ...counts.entries.map((e) => _teamChip(
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
            const SizedBox(height: 12),
          ],
          Row(children: [
            const Icon(Icons.sort, size: 15, color: Colors.grey),
            const SizedBox(width: 5),
            const Text('ORDENAR',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _sortChip('Por hangar', Icons.warehouse, _Sort.hangar),
                _sortChip(
                    'Mais antigas', Icons.arrow_upward, _Sort.antigas),
                _sortChip(
                    'Mais recentes', Icons.arrow_downward, _Sort.recentes),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortChip(String label, IconData icon, _Sort mode) {
    final selected = _sort == mode;
    const color = Color(0xFF1E3A5F);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _sort = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color : color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(17),
            border:
                Border.all(color: selected ? color : color.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: selected ? Colors.white : color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : color)),
          ]),
        ),
      ),
    );
  }

  Widget _teamChip({
    required String label,
    required int count,
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
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
                color: selected ? color : color.withOpacity(0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (selected) ...[
              const Icon(Icons.check, size: 14, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : color,
              ),
            ),
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
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Text(
            _isProducerMode
                ? widget.lockedProducer!
                : 'Pendências por Produtor',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17)),
        actions: [
          if (_selected != null && _visible.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.white),
              tooltip: 'Copiar para WhatsApp',
              onPressed: _copyWhatsApp,
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_isProducerMode)
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
                                child: Text(p,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: sel
                                            ? Colors.white
                                            : Colors.black87,
                                        fontSize: 14)),
                              ),
                            );
                          }).toList(),
                        ),
                ],
              ),
            ),

          if (_selected != null && !_loading && _items.isNotEmpty)
            _teamFilterBar(),

          Expanded(
            child: _selected == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_search, size: 64, color: Colors.grey),
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
                        : _visible.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.filter_alt_off,
                                        size: 56, color: Colors.grey),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Nenhuma pendência para\na equipe selecionada.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.grey, fontSize: 15),
                                    ),
                                    const SizedBox(height: 12),
                                    TextButton.icon(
                                      onPressed: () =>
                                          setState(_teamFilter.clear),
                                      icon: const Icon(Icons.clear_all,
                                          size: 18),
                                      label: const Text('Mostrar todas'),
                                    ),
                                  ],
                                ),
                              )
                            : _sort == _Sort.hangar
                                ? _PendingList(
                                    grouped: _grouped,
                                    totalItems: _visible.length,
                                    produtor: _selected!,
                                    canResolve: widget.canResolve,
                                    onCopy: _copyWhatsApp,
                                    onResolve: _resolveItem,
                                  )
                                : _ChronoList(
                                    items: _byDate,
                                    produtor: _selected!,
                                    oldestFirst: _sort == _Sort.antigas,
                                    canResolve: widget.canResolve,
                                    onResolve: _resolveItem,
                                  ),
          ),
        ],
      ),
      floatingActionButton:
          (_selected != null && _visible.isNotEmpty && !_loading)
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

/// Lista corrida em ordem cronológica, com a idade de cada pendência em
/// destaque — no modo "mais antigas" é o que mostra o que está parado há
/// mais tempo.
class _ChronoList extends StatelessWidget {
  final List<PendingItem> items;
  final String produtor;
  final bool oldestFirst;
  final bool canResolve;
  final Future<void> Function(PendingItem) onResolve;

  const _ChronoList({
    required this.items,
    required this.produtor,
    required this.oldestFirst,
    required this.canResolve,
    required this.onResolve,
  });

  static final _fmt = DateFormat('dd/MM/yyyy HH:mm');

  static String _age(DateTime d) {
    final days = DateTime.now().difference(d).inDays;
    if (days <= 0) return 'hoje';
    if (days == 1) return 'há 1 dia';
    return 'há $days dias';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.orange.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(oldestFirst ? Icons.history : Icons.schedule,
                color: Colors.orange, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${items.length} pendência${items.length != 1 ? "s" : ""} — '
                '${oldestFirst ? "mais antigas primeiro" : "mais recentes primeiro"}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              final days = DateTime.now().difference(item.createdAt).inDays;
              final urgent = days >= 2;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: urgent
                                ? Colors.red.shade50
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _age(item.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: urgent
                                  ? Colors.red.shade700
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(_fmt.format(item.createdAt),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        '${item.local.isNotEmpty ? "Stand ${item.local}" : "Sem stand"}'
                        '${item.hangar.isNotEmpty ? " · Hangar ${item.hangar}" : ""}'
                        '${item.clientName.isNotEmpty ? " — ${item.clientName}" : ""}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const Divider(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TeamDot(team: item.team),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.team +
                                      (item.responsible.isNotEmpty
                                          ? ' · ${item.responsible}'
                                          : ''),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: Colors.grey.shade700),
                                ),
                                Text(item.description,
                                    style: const TextStyle(fontSize: 13)),
                                FurniturePickChips(items: item.furnitureItems, dense: true),
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
                            onPressed: () => onResolve(item),
                            icon: const Icon(Icons.check, size: 14),
                            label: const Text('Resolver',
                                style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                                  CrossAxisAlignment.start,
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
                                                FurniturePickChips(items: item.furnitureItems, dense: true),
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
                                            onPressed: () => onResolve(item),
                                            icon: const Icon(Icons.check,
                                                size: 14),
                                            label: const Text('Resolver',
                                                style:
                                                    TextStyle(fontSize: 12)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
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

/// Cor da equipe — compartilhada entre o marcador da lista e os chips de filtro.
Color teamColor(String team) {
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

class _TeamDot extends StatelessWidget {
  final String team;
  const _TeamDot({required this.team});

  Color get _color => teamColor(team);

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(top: 3),
        decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
      );
}
