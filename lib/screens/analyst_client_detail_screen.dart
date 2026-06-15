import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_provider.dart';
import '../models/client.dart';
import '../models/pending_item.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../widgets/photo_gallery.dart';
import '../widgets/montage_section.dart';
import '../widgets/client_specs_card.dart';
import '../widgets/analyst_notes_widget.dart';

class AnalystClientDetailScreen extends StatefulWidget {
  final Client client;
  final String analystName;

  const AnalystClientDetailScreen({
    super.key,
    required this.client,
    required this.analystName,
  });

  @override
  State<AnalystClientDetailScreen> createState() =>
      _AnalystClientDetailScreenState();
}

class _AnalystClientDetailScreenState
    extends State<AnalystClientDetailScreen> {
  List<PendingItem> _items = [];
  List<PendingItem> _awaitingItems = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
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
        _awaitingItems = awaitingItems;
        _loading = false;
      });
    }
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
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    final provider = context.read<AppProvider>();
    final awaitingIds = {
      for (final a in _awaitingItems)
        if (a.firestoreId != null) a.firestoreId!
    };
    final open = _items
        .where((p) =>
            !p.isResolved &&
            (p.firestoreId == null || !awaitingIds.contains(p.firestoreId)))
        .toList();
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
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    if (c.hangar.isNotEmpty)
                      _chip(Icons.warehouse, 'Hangar ${c.hangar}'),
                    if (c.local.isNotEmpty) _chip(Icons.grid_on, c.local),
                    if (c.area.isNotEmpty)
                      _chip(Icons.square_foot, '${c.area} m²'),
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

            // Responsáveis
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
                        _RespChip(
                            'Limpeza', c.faxineira, Colors.cyan.shade700),
                      if (c.teto50.isNotEmpty)
                        _RespChip('Teto 50', c.teto50, Colors.teal),
                      _RespChip('Vidraceiro', 'Rodrigo', Colors.lightBlue),
                      _RespChip('Com. Visual', 'Vinícius', Colors.pink),
                    ],
                  ),
                ),
              ),
            ),

            // Links
            if (c.projectLink.isNotEmpty)
              _linkTile(
                  Icons.link, 'Ver projeto no Drive', c.projectLink, Colors.blue),
            if (c.linkCv.isNotEmpty)
              _linkTile(Icons.image_outlined, 'Ver print Comunicação Visual',
                  c.linkCv, Colors.pink),
            if (c.linkMemorial.isNotEmpty)
              _linkTile(Icons.description_outlined, 'Ver Memorial Descritivo',
                  c.linkMemorial, Colors.teal),

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
                                style: const TextStyle(fontSize: 14))),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // Specs (read-only)
            ClientSpecsCard(clientId: c.rowId),

            // Analyst notes (editable by analyst)
            AnalystNotesWidget(
              clientId: c.rowId,
              canEdit: true,
              editorName: widget.analystName,
            ),

            // Montage photos (view-only)
            MontageSection(
              clientId: c.rowId,
              fairId: c.fairId,
              fairName: provider.currentFairName,
              canAdd: false,
            ),

            // Pending items (read-only)
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()))
            else ...[
              if (open.isNotEmpty) ...[
                _SectionTitle(
                    text: 'PENDÊNCIAS ABERTAS (${open.length})',
                    color: Colors.orange),
                ...open.map((item) => _ReadOnlyPendingCard(item: item)),
              ],
              if (_awaitingItems.isNotEmpty) ...[
                _SectionTitle(
                    text: 'AGUARDANDO VALIDAÇÃO (${_awaitingItems.length})',
                    color: Colors.blue),
                ...(_awaitingItems
                    .map((item) => _ReadOnlyPendingCard(item: item, awaiting: true))),
              ],
              if (resolved.isNotEmpty) ...[
                _SectionTitle(
                    text: 'RESOLVIDAS (${resolved.length})',
                    color: Colors.green),
                ...resolved.map((item) => _ReadOnlyPendingCard(item: item)),
              ],
              if (_items.isEmpty && _awaitingItems.isEmpty)
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
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );

  Widget _linkTile(
      IconData icon, String label, String url, MaterialColor color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: InkWell(
        onTap: () => _launchUrl(url),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.shade200),
          ),
          child: Row(children: [
            Icon(icon, color: color.shade700, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: color.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            ),
            Icon(Icons.open_in_new, color: color.shade400, size: 16),
          ]),
        ),
      ),
    );
  }

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

class _ReadOnlyPendingCard extends StatelessWidget {
  final PendingItem item;
  final bool awaiting;
  const _ReadOnlyPendingCard({required this.item, this.awaiting = false});

  @override
  Widget build(BuildContext context) {
    final resolved = item.isResolved;
    Color borderColor = resolved
        ? Colors.green.shade200
        : awaiting
            ? Colors.blue.shade200
            : Colors.orange.shade200;
    Color bgColor = resolved
        ? Colors.green.shade50
        : awaiting
            ? Colors.blue.shade50
            : Colors.white;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: bgColor,
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
              _StatusDot(
                  color: resolved
                      ? Colors.green
                      : awaiting
                          ? Colors.amber
                          : Colors.deepOrange),
              const SizedBox(width: 8),
              _TeamBadge(team: item.team),
              if (item.responsible.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(item.responsible,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12)),
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
                ])
              else if (awaiting)
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
                )
              else if (item.inProgress && item.inProgressBy.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.deepPurple.shade200),
                  ),
                  child: Text('Em andamento por ${item.inProgressBy}',
                      style: TextStyle(
                          color: Colors.deepPurple.shade600,
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
              'Criada em ${_fmt(item.createdAt)}'
              '${item.createdBy.isNotEmpty ? ' • ${item.createdBy}' : ''}'
              '${item.resolvedAt != null ? '\nResolvida em ${_fmt(item.resolvedAt!)}${item.resolvedBy.isNotEmpty ? ' • ${item.resolvedBy}' : ''}' : ''}',
              style: const TextStyle(color: Colors.grey, fontSize: 11),
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
