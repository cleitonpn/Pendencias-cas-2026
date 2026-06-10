import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_provider.dart';
import '../models/client.dart';
import '../models/pending_item.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../widgets/photo_gallery.dart';
import '../widgets/montage_section.dart';
import 'add_pending_screen.dart';
import 'edit_pending_screen.dart';

class ClientDetailScreen extends StatefulWidget {
  final Client client;
  const ClientDetailScreen({super.key, required this.client});

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  List<PendingItem> _items = [];
  List<PendingItem> _awaitingFirestoreItems = [];
  bool _loading = false;
  AppProvider? _provider;

  @override
  void initState() {
    super.initState();
    _load();
    _provider = context.read<AppProvider>();
    _provider!.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _provider?.removeListener(_onProviderChanged);
    super.dispose();
  }

  // Real-time: when the Firestore stream updates the provider, reload quietly.
  void _onProviderChanged() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final sqliteItems =
        await DatabaseService.getPendingItemsByClient(widget.client.rowId);
    List<PendingItem> awaitingItems = [];
    try {
      awaitingItems = await FirestoreService.getAwaitingItemsByClientId(
          widget.client.rowId);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _items = sqliteItems;
        _awaitingFirestoreItems = awaitingItems;
        _loading = false;
      });
    }
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
            builder: (_) => AddPendingScreen(
                client: widget.client, createdBy: 'Administrador')));
    if (item != null) {
      _items.insert(0, item);
      setState(() {});
    }
  }

  Future<bool> _confirm(String title, String message, String confirmLabel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _resolve(PendingItem item) async {
    if (!await _confirm('Resolver pendência?',
        'Marcar esta pendência como resolvida? Esta ação não pode ser desfeita.',
        'Resolver')) return;
    await context.read<AppProvider>().resolveItem(item.id!,
        firestoreId: item.firestoreId, by: 'Administrador');
    await _load();
  }

  Future<void> _validateByFirestoreId(String firestoreId) async {
    if (!await _confirm('Validar pendência?',
        'Validar e concluir esta pendência? Esta ação não pode ser desfeita.',
        'Validar')) return;
    await context.read<AppProvider>().validateItemByFirestoreId(firestoreId,
        by: 'Administrador');
    await _load();
  }

  Future<void> _edit(PendingItem item) async {
    final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => EditPendingScreen(item: item, client: widget.client)));
    if (changed == true) await _load();
  }

  Future<void> _launchUrl(String url) async {
    String target = url.trim();
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      target = 'https://$target';
    }
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível abrir o link.')));
      }
    }
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
    // Build set of awaiting firestoreIds for quick lookup
    final awaitingIds = {
      for (final a in _awaitingFirestoreItems)
        if (a.firestoreId != null) a.firestoreId!
    };
    // Open items: unresolved SQLite items NOT in awaiting set
    final open = _items.where((p) =>
        !p.isResolved &&
        (p.firestoreId == null || !awaitingIds.contains(p.firestoreId))).toList();
    // Awaiting: firestoreItems from Firestore that are awaiting validation
    // merged with SQLite items that match (to get sqliteId for resolution)
    final awaitingItems = _awaitingFirestoreItems;
    final resolved = _items.where((p) => p.isResolved).toList();
    final headerColor =
        c.isCompleted ? Colors.green.shade700 : const Color(0xFF1E3A5F);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: headerColor,
        title: Text(c.local.isNotEmpty ? 'Stand ${c.local}' : c.displayName,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(
                c.isCompleted
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
                color: Colors.white),
            tooltip:
                c.isCompleted ? 'Desfazer conclusão' : 'Marcar concluído',
            onPressed: _toggle,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header info
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
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    if (c.hangar.isNotEmpty)
                      _chip(Icons.warehouse, 'Hangar ${c.hangar}'),
                    if (c.local.isNotEmpty) _chip(Icons.grid_on, c.local),
                    if (c.area.isNotEmpty) _chip(Icons.square_foot, '${c.area} m²'),
                    if (c.montagem.isNotEmpty)
                      _chip(Icons.business, c.montagem),
                  ]),
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

            // Responsáveis (colunas O-T)
            if (_hasResp(c)) ...[
              const _SectionTitle(
                  text: 'RESPONSÁVEIS POR EQUIPE', color: Colors.grey),
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
                        if (c.produtor.isNotEmpty)
                          _RespChip('Produtor', c.produtor, Colors.indigo),
                        if (c.marceneiro.isNotEmpty)
                          _RespChip('Marcenaria', c.marceneiro, Colors.brown),
                        if (c.tapeceiro.isNotEmpty)
                          _RespChip('Tapeçaria', c.tapeceiro, Colors.purple),
                        if (c.eletricista.isNotEmpty)
                          _RespChip('Elétrica', c.eletricista, Colors.orange),
                        if (c.faxineira.isNotEmpty)
                          _RespChip('Limpeza', c.faxineira, Colors.cyan.shade700),
                        if (c.teto50.isNotEmpty)
                          _RespChip('Teto 50', c.teto50, Colors.teal),
                        _RespChip('Vidraceiro', 'Rodrigo', Colors.lightBlue),
                        _RespChip('Com. Visual', 'Vinícius', Colors.pink),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // Project link
            if (c.projectLink.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: InkWell(
                  onTap: () => _launchUrl(c.projectLink),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.link, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Ver projeto no Drive',
                          style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                        ),
                      ),
                      Icon(Icons.open_in_new,
                          color: Colors.blue.shade400, size: 16),
                    ]),
                  ),
                ),
              ),

            if (c.linkCv.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: InkWell(
                  onTap: () => _launchUrl(c.linkCv),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.pink.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.pink.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.image_outlined, color: Colors.pink.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Ver print Comunicação Visual',
                          style: TextStyle(
                              color: Colors.pink.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                        ),
                      ),
                      Icon(Icons.open_in_new, color: Colors.pink.shade400, size: 16),
                    ]),
                  ),
                ),
              ),

            // Mobiliário locado
            if (c.mobilario.isNotEmpty) ...[
              const _SectionTitle(
                  text: 'MOBILIÁRIO LOCADO', color: Colors.teal),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.chair_outlined,
                            color: Colors.teal, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(c.mobilario,
                              style: const TextStyle(fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // Botões de ação
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _toggle,
                      icon: Icon(c.isCompleted ? Icons.undo : Icons.check),
                      label:
                          Text(c.isCompleted ? 'Desfazer' : 'Concluído'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            c.isCompleted ? Colors.grey : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Montage progress photos (admin only views)
            MontageSection(
              clientId: c.rowId,
              fairId: c.fairId,
              fairName: context.read<AppProvider>().currentFairName,
              canAdd: false,
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
                    onEdit: () => _edit(item),
                    onCopy: () => _copyWhatsApp(item))),
              ],
              if (awaitingItems.isNotEmpty) ...[
                _SectionTitle(
                    text: 'AGUARDANDO VALIDAÇÃO (${awaitingItems.length})',
                    color: Colors.blue),
                ...awaitingItems.map((item) {
                  // Find matching SQLite item for this firestoreId (if exists)
                  final sqliteMatch = item.firestoreId != null
                      ? _items.where((i) =>
                              i.firestoreId == item.firestoreId &&
                              !i.isResolved)
                          .firstOrNull
                      : null;
                  return _AwaitingCard(
                    item: item,
                    onValidate: () => sqliteMatch != null
                        ? _resolve(sqliteMatch)
                        : _validateByFirestoreId(item.firestoreId!),
                    onCopy: () => _copyWhatsApp(item),
                  );
                }),
              ],
              if (resolved.isNotEmpty) ...[
                _SectionTitle(
                    text: 'RESOLVIDAS (${resolved.length})',
                    color: Colors.green),
                ...resolved.map((item) => _PendingCard(
                    item: item,
                    onResolve: null,
                    onEdit: null,
                    onCopy: () => _copyWhatsApp(item))),
              ],
              if (_items.isEmpty && awaitingItems.isEmpty)
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
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );

  // Vidraceiro (Rodrigo) e Com. Visual (Vinícius) atendem todos — seção sempre visível
  bool _hasResp(Client c) => true;

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            Text(person, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}

class _PendingCard extends StatelessWidget {
  final PendingItem item;
  final VoidCallback? onResolve;
  final VoidCallback? onEdit;
  final VoidCallback onCopy;

  const _PendingCard(
      {required this.item,
      required this.onResolve,
      this.onEdit,
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
            Row(children: [
              _StatusDot(color: resolved ? Colors.green : Colors.deepOrange),
              const SizedBox(width: 8),
              _TeamBadge(team: item.team),
              if (item.responsible.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(item.responsible,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12)),
                ),
              ],
              const Spacer(),
              if (resolved)
                const Row(children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 4),
                  Text('Resolvido',
                      style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ]),
            ]),
            const SizedBox(height: 8),
            if (item.fromClient) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.storefront, size: 13, color: Colors.orange),
                  SizedBox(width: 4),
                  Text('Solicitado pelo expositor',
                      style: TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
            Text(item.description, style: const TextStyle(fontSize: 14)),
            if (item.photoUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              PhotoStrip(urls: item.photoUrls),
            ],
            const SizedBox(height: 6),
            Text(
              'Criada em ${_fmt(item.createdAt)}'
              '${item.createdBy.isNotEmpty ? ' • ${item.createdBy}' : ''}'
              '${item.resolvedAt != null ? '\nResolvida em ${_fmt(item.resolvedAt!)}${item.resolvedBy.isNotEmpty ? ' • ${item.resolvedBy}' : ''}' : ''}',
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('WhatsApp',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF25D366),
                  side: const BorderSide(color: Color(0xFF25D366)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
              if (onEdit != null) ...[
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Editar',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1E3A5F),
                    side: const BorderSide(color: Color(0xFF1E3A5F)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
              if (onResolve != null)
                ElevatedButton.icon(
                  onPressed: onResolve,
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Resolver',
                      style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _AwaitingCard extends StatelessWidget {
  final PendingItem item;
  final VoidCallback onValidate;
  final VoidCallback onCopy;

  const _AwaitingCard(
      {required this.item, required this.onValidate, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
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
              const _StatusDot(color: Colors.amber),
              const SizedBox(width: 8),
              _TeamBadge(team: item.team),
              if (item.responsible.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(item.responsible,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12)),
                ),
              ],
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Aguardando validação',
                    style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 8),
            if (item.fromClient) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.storefront, size: 13, color: Colors.orange),
                  SizedBox(width: 4),
                  Text('Solicitado pelo expositor',
                      style: TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
            Text(item.description, style: const TextStyle(fontSize: 14)),
            if (item.photoUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              PhotoStrip(urls: item.photoUrls),
            ],
            const SizedBox(height: 6),
            Text(
              _fmt(item.createdAt),
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
            const SizedBox(height: 10),
            Row(children: [
              OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('WhatsApp',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF25D366),
                  side: const BorderSide(color: Color(0xFF25D366)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: onValidate,
                icon: const Icon(Icons.verified, size: 14),
                label: const Text('Validar',
                    style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _StatusDot extends StatelessWidget {
  final Color color;
  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
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
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
