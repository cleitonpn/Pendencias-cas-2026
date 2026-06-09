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
import 'add_pending_screen.dart';

/// Read-only client detail for the Consultant role.
/// The consultant can browse everything and CREATE pending items, but cannot
/// resolve, validate, or mark anything as complete.
class ConsultantClientDetailScreen extends StatefulWidget {
  final Client client;
  final String consultantName;
  const ConsultantClientDetailScreen(
      {super.key, required this.client, this.consultantName = ''});

  @override
  State<ConsultantClientDetailScreen> createState() =>
      _ConsultantClientDetailScreenState();
}

class _ConsultantClientDetailScreenState
    extends State<ConsultantClientDetailScreen> {
  List<PendingItem> _items = [];
  Set<String> _awaitingIds = {};
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

  void _onProviderChanged() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final items =
        await DatabaseService.getPendingItemsByClient(widget.client.rowId);
    List<PendingItem> awaiting = [];
    try {
      awaiting =
          await FirestoreService.getAwaitingItemsByClientId(widget.client.rowId);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _items = items;
        _awaitingIds = awaiting.map((i) => i.firestoreId ?? '').toSet()
          ..remove('');
        _loading = false;
      });
    }
  }

  Future<void> _addPending() async {
    final item = await Navigator.push<PendingItem>(
        context,
        MaterialPageRoute(
            builder: (_) => AddPendingScreen(
                client: widget.client,
                createdBy: widget.consultantName.isNotEmpty
                    ? 'Consultor: ${widget.consultantName}'
                    : 'Consultor')));
    if (item != null) {
      _items.insert(0, item);
      setState(() {});
    }
  }

  bool _isAwaiting(PendingItem item) =>
      item.firestoreId != null && _awaitingIds.contains(item.firestoreId);

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
    final open = _items
        .where((p) => !p.isResolved && !_isAwaiting(p))
        .toList();
    final awaiting =
        _items.where((p) => !p.isResolved && _isAwaiting(p)).toList();
    final resolved = _items.where((p) => p.isResolved).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Text(c.local.isNotEmpty ? 'Stand ${c.local}' : c.displayName,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              color: const Color(0xFF1E3A5F),
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
                    if (c.area.isNotEmpty)
                      _chip(Icons.square_foot, '${c.area} m²'),
                    if (c.montagem.isNotEmpty) _chip(Icons.business, c.montagem),
                  ]),
                ],
              ),
            ),

            // Responsibles
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
                      _RespChip('Vidraceiro', 'Rodrigo', Colors.lightBlue),
                      _RespChip('Com. Visual', 'Vinícius', Colors.pink),
                    ],
                  ),
                ),
              ),
            ),

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
                        child: Text('Ver projeto no Drive',
                            style: TextStyle(
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                      Icon(Icons.open_in_new,
                          color: Colors.blue.shade400, size: 16),
                    ]),
                  ),
                ),
              ),

            if (c.linkCv.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: InkWell(
                  onTap: () => _launchUrl(c.linkCv),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.pink.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.pink.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.image_outlined,
                          color: Colors.pink.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Ver print Comunicação Visual',
                            style: TextStyle(
                                color: Colors.pink.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                      Icon(Icons.open_in_new,
                          color: Colors.pink.shade400, size: 16),
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

            // Create pending button (the only action available)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _addPending,
                  icon: const Icon(Icons.add),
                  label: const Text('Criar Pendência'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
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
                    item: item, badge: null, onCopy: () => _copyWhatsApp(item))),
              ],
              if (awaiting.isNotEmpty) ...[
                _SectionTitle(
                    text: 'AGUARDANDO VALIDAÇÃO (${awaiting.length})',
                    color: Colors.blue),
                ...awaiting.map((item) => _PendingCard(
                    item: item,
                    badge: _Badge('Aguardando validação', Colors.blue),
                    onCopy: () => _copyWhatsApp(item))),
              ],
              if (resolved.isNotEmpty) ...[
                _SectionTitle(
                    text: 'RESOLVIDAS (${resolved.length})',
                    color: Colors.green),
                ...resolved.map((item) => _PendingCard(
                    item: item,
                    badge: _Badge('Resolvido', Colors.green),
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );
}

class _Badge {
  final String text;
  final MaterialColor color;
  _Badge(this.text, this.color);
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
                    fontSize: 10, color: color, fontWeight: FontWeight.bold)),
            Text(person, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}

class _PendingCard extends StatelessWidget {
  final PendingItem item;
  final _Badge? badge;
  final VoidCallback onCopy;

  const _PendingCard(
      {required this.item, required this.badge, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final bg = badge?.color.shade50 ?? Colors.white;
    final border = badge?.color.shade200 ?? Colors.orange.shade200;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
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
              _TeamBadge(team: item.team),
              if (item.responsible.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(item.responsible,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
              const Spacer(),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badge!.color.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(badge!.text,
                      style: TextStyle(
                          color: badge!.color.shade700,
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
            Text(_fmt(item.createdAt),
                style: const TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('WhatsApp', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF25D366),
                side: const BorderSide(color: Color(0xFF25D366)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
              ),
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
                color: _color, fontSize: 12, fontWeight: FontWeight.bold)),
      );
}
