import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/client.dart';
import '../models/pending_item.dart';
import '../services/database_service.dart';
import 'add_pending_screen.dart';

class ClientDetailScreen extends StatefulWidget {
  final Client client;
  const ClientDetailScreen({super.key, required this.client});

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  List<PendingItem> _items = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _items = await DatabaseService.getPendingItemsByClient(
        widget.client.rowId);
    setState(() => _loading = false);
  }

  Future<void> _toggle() async {
    final newVal = !widget.client.isCompleted;
    await context.read<AppProvider>().markClientCompleted(widget.client, newVal);
    setState(() {});
    if (newVal && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Stand marcado como concluído!'),
          backgroundColor: Colors.green));
    }
  }

  Future<void> _addPending() async {
    final item = await Navigator.push<PendingItem>(
        context,
        MaterialPageRoute(
            builder: (_) => AddPendingScreen(client: widget.client)));
    if (item != null) {
      _items.insert(0, item);
      setState(() {});
    }
  }

  Future<void> _resolve(PendingItem item) async {
    await context.read<AppProvider>().resolveItem(item.id!);
    await _load();
  }

  void _copyWhatsApp(PendingItem item) {
    Clipboard.setData(ClipboardData(text: item.toWhatsAppText()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Texto copiado! Cole no WhatsApp.'),
        backgroundColor: Color(0xFF25D366),
        duration: Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    final open = _items.where((p) => !p.isResolved).toList();
    final resolved = _items.where((p) => p.isResolved).toList();
    final headerColor =
        c.isCompleted ? Colors.green.shade700 : const Color(0xFF1E3A5F);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: headerColor,
        title: Text('Stand ${c.stand}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(
                c.isCompleted
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
                color: Colors.white),
            tooltip: c.isCompleted ? 'Desfazer conclusão' : 'Marcar concluído',
            onPressed: _toggle,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              color: headerColor,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.displayName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _chip(Icons.warehouse, 'Hangar ${c.hangar}'),
                      _chip(Icons.grid_on, 'Stand ${c.stand}'),
                      if (c.block.isNotEmpty)
                        _chip(Icons.view_module, 'Bloco ${c.block}'),
                    ],
                  ),
                  if (c.montagem.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(c.montagem,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12)),
                  ],
                  if (c.isCompleted && c.completedAt != null) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.check_circle,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text('Concluído em ${_fmtDate(c.completedAt!)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 13)),
                    ]),
                  ],
                ],
              ),
            ),

            // Responsible people
            if (_hasResp(c)) ...[
              const _SectionTitle(text: 'RESPONSÁVEIS', color: Colors.grey),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (c.respProdutos.isNotEmpty)
                          _RespChip('Produtos', c.respProdutos, Colors.teal),
                        if (c.respMontagem.isNotEmpty)
                          _RespChip('Montagem', c.respMontagem, Colors.indigo),
                        if (c.respTapecaria.isNotEmpty)
                          _RespChip('Tapeçaria', c.respTapecaria, Colors.purple),
                        if (c.respEletrica.isNotEmpty)
                          _RespChip('Elétrica', c.respEletrica, Colors.orange),
                        if (c.respLaminacao.isNotEmpty)
                          _RespChip('Laminação', c.respLaminacao, Colors.blue),
                        if (c.respMK.isNotEmpty)
                          _RespChip('MK', c.respMK, Colors.pink),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _toggle,
                      icon:
                          Icon(c.isCompleted ? Icons.undo : Icons.check),
                      label: Text(c.isCompleted
                          ? 'Desfazer'
                          : 'Concluído'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            c.isCompleted ? Colors.grey : Colors.green,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _addPending,
                      icon: const Icon(Icons.add),
                      label: const Text('Pendência'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()))
            else ...[
              if (open.isNotEmpty) ...[
                _SectionTitle(
                    text: 'PENDÊNCIAS ABERTAS (${open.length})',
                    color: Colors.orange),
                ...open.map((item) => _PendingCard(
                    item: item,
                    onResolve: () => _resolve(item),
                    onCopy: () => _copyWhatsApp(item))),
              ],
              if (resolved.isNotEmpty) ...[
                _SectionTitle(
                    text: 'RESOLVIDAS (${resolved.length})',
                    color: Colors.green),
                ...resolved.map((item) => _PendingCard(
                    item: item,
                    onResolve: null,
                    onCopy: () => _copyWhatsApp(item))),
              ],
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('Nenhuma pendência registrada.',
                          style: TextStyle(color: Colors.grey))),
                ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(label,
                style:
                    const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      );

  bool _hasResp(Client c) =>
      c.respProdutos.isNotEmpty ||
      c.respMontagem.isNotEmpty ||
      c.respTapecaria.isNotEmpty ||
      c.respEletrica.isNotEmpty ||
      c.respLaminacao.isNotEmpty ||
      c.respMK.isNotEmpty;

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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

class _RespChip extends StatelessWidget {
  final String team, person;
  final Color color;
  const _RespChip(this.team, this.person, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(team,
                style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.bold)),
            Text(person, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}

class _PendingCard extends StatelessWidget {
  final PendingItem item;
  final VoidCallback? onResolve;
  final VoidCallback onCopy;

  const _PendingCard(
      {required this.item,
      required this.onResolve,
      required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final resolved = item.isResolved;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: resolved ? Colors.green.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: resolved
                ? Colors.green.shade200
                : Colors.orange.shade200),
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
            Row(
              children: [
                _TeamBadge(team: item.team),
                const Spacer(),
                if (resolved)
                  const Row(children: [
                    Icon(Icons.check_circle,
                        color: Colors.green, size: 16),
                    SizedBox(width: 4),
                    Text('Resolvido',
                        style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ]),
              ],
            ),
            const SizedBox(height: 8),
            Text(item.description,
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 6),
            Text(
              _fmt(item.createdAt) +
                  (item.resolvedAt != null
                      ? '\nResolvido: ${_fmt(item.resolvedAt!)}'
                      : ''),
              style: const TextStyle(
                  color: Colors.grey, fontSize: 11),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('WhatsApp',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side: const BorderSide(color: Color(0xFF25D366)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                ),
                if (onResolve != null) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: onResolve,
                    icon: const Icon(Icons.check, size: 14),
                    label: const Text('Resolver',
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _TeamBadge extends StatelessWidget {
  final String team;
  const _TeamBadge({required this.team});

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
      case 'laminação':
      case 'laminacao':
        return Colors.blue;
      case 'produtos':
        return Colors.teal;
      case 'montagem':
        return Colors.indigo;
      case 'mk':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _color.withOpacity(0.4)),
        ),
        child: Text(team,
            style: TextStyle(
                color: _color,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      );
}
