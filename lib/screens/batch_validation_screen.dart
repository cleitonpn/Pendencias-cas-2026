import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pending_item.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../widgets/resolution_dialog.dart';

/// Allows the admin to select one or more pending items that are awaiting
/// validation and conclude (resolve) them all at once.
class BatchValidationScreen extends StatefulWidget {
  const BatchValidationScreen({super.key});

  @override
  State<BatchValidationScreen> createState() => _BatchValidationScreenState();
}

class _BatchValidationScreenState extends State<BatchValidationScreen> {
  static const _navy = Color(0xFF1E3A5F);

  static const _teamColors = <String, Color>{
    'Limpeza':            Color(0xFF00897B),
    'Elétrica':           Color(0xFFFF6F00),
    'Marcenaria':         Color(0xFF795548),
    'Tapeçaria':          Color(0xFF7B1FA2),
    'Vidraceiro':         Color(0xFF0288D1),
    'Comunicação Visual': Color(0xFFD81B60),
  };

  List<PendingItem> _items = [];
  final Set<String> _selected = {}; // unique key per item
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    final fair = context.read<AppProvider>().currentFair;
    if (fair?.id == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!silent) {
      if (mounted) setState(() => _loading = true);
    }
    final all = await DatabaseService.getAllPendingItems(fairId: fair!.id!);
    final awaiting = all
        .where((p) => !p.isResolved && p.awaitingValidation)
        .toList()
      ..sort((a, b) {
        final h = a.hangar.compareTo(b.hangar);
        if (h != 0) return h;
        return a.local.compareTo(b.local);
      });
    if (mounted) {
      setState(() {
        _items = awaiting;
        // Remove keys that no longer exist (item was already resolved).
        _selected.removeWhere(
            (k) => !awaiting.any((p) => _key(p) == k));
        _loading = false;
      });
    }
  }

  String _key(PendingItem item) =>
      item.firestoreId?.isNotEmpty == true
          ? item.firestoreId!
          : 'sqlite_${item.id}';

  bool _isSelected(PendingItem item) => _selected.contains(_key(item));

  void _toggle(PendingItem item) {
    setState(() {
      final k = _key(item);
      if (_selected.contains(k)) {
        _selected.remove(k);
      } else {
        _selected.add(k);
      }
    });
  }

  void _toggleAll() {
    setState(() {
      if (_selected.length == _items.length) {
        _selected.clear();
      } else {
        _selected.addAll(_items.map(_key));
      }
    });
  }

  Future<void> _validateSelected() async {
    final toValidate =
        _items.where((p) => _selected.contains(_key(p))).toList();
    if (toValidate.isEmpty) return;

    // A nota vale para todas as selecionadas — é uma conclusão em lote.
    final r = await showResolutionDialog(
      context,
      fairId: context.read<AppProvider>().currentFair?.id ?? 1,
      title: 'Concluir em lote?',
      message: 'Validar e concluir ${toValidate.length} '
          'pendência${toValidate.length != 1 ? "s" : ""}. A nota e as fotos '
          'são opcionais e serão aplicadas a todas as selecionadas.',
      confirmLabel: 'Concluir tudo',
    );
    if (r == null || !mounted) return;

    setState(() => _saving = true);
    await context.read<AppProvider>().batchValidateItems(toValidate,
        note: r.note, photoUrls: r.photoUrls);
    if (!mounted) return;
    _selected.clear();
    await _load(silent: true);
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '${toValidate.length} '
          'pendência${toValidate.length != 1 ? "s" : ""} '
          'concluída${toValidate.length != 1 ? "s" : ""}!',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _items.isNotEmpty && _selected.length == _items.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: _navy,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Validação em lote',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            if (!_loading)
              Text(
                '${_items.length} aguardando validação',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.75), fontSize: 12),
              ),
          ],
        ),
        actions: [
          if (!_loading && _items.isNotEmpty)
            TextButton(
              onPressed: _saving ? null : _toggleAll,
              child: Text(
                allSelected ? 'Nenhuma' : 'Todas',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 72, color: Colors.green.shade300),
                      const SizedBox(height: 16),
                      const Text(
                        'Nenhuma pendência\naguardando validação',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    final sel = _isSelected(item);
                    final color =
                        _teamColors[item.team] ?? Colors.grey;
                    return _ItemCard(
                      item: item,
                      teamColor: color,
                      selected: sel,
                      enabled: !_saving,
                      onTap: () => _toggle(item),
                    );
                  },
                ),
      bottomNavigationBar: _items.isEmpty || _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: ElevatedButton.icon(
                  onPressed:
                      _selected.isEmpty || _saving ? null : _validateSelected,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_circle),
                  label: Text(
                    _selected.isEmpty
                        ? 'Selecione pendências para concluir'
                        : 'Concluir ${_selected.length} '
                            'selecionada${_selected.length != 1 ? "s" : ""}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade500,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final PendingItem item;
  final Color teamColor;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ItemCard({
    required this.item,
    required this.teamColor,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: selected ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? Colors.green : Colors.grey.shade200,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Checkbox
              Checkbox(
                value: selected,
                activeColor: Colors.green,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
                onChanged: enabled ? (_) => onTap() : null,
              ),
              // Team color bar
              Container(
                width: 4,
                height: 50,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: teamColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: teamColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.team,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: teamColor),
                        ),
                      ),
                      const Spacer(),
                      if (item.local.isNotEmpty)
                        Text(
                          'Stand ${item.local}'
                          '${item.hangar.isNotEmpty ? " · H${item.hangar}" : ""}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500),
                        ),
                    ]),
                    const SizedBox(height: 3),
                    Text(
                      item.clientName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.description.isNotEmpty)
                      Text(
                        item.description,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
