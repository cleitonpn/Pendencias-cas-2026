import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/client.dart';
import '../models/pending_item.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../widgets/photo_gallery.dart';

class ProducerClientDetailScreen extends StatefulWidget {
  final Client client;
  const ProducerClientDetailScreen({super.key, required this.client});

  @override
  State<ProducerClientDetailScreen> createState() =>
      _ProducerClientDetailScreenState();
}

class _ProducerClientDetailScreenState
    extends State<ProducerClientDetailScreen> {
  List<PendingItem> _items = [];
  Set<String> _awaitingFirestoreIds = {};
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

  // Real-time: reload quietly when the Firestore stream updates the provider.
  void _onProviderChanged() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final items = await DatabaseService.getPendingItemsByClient(
        widget.client.rowId);
    final awaitingItems = await FirestoreService.getAwaitingItemsByClientId(
        widget.client.rowId);
    if (mounted) {
      setState(() {
        _items = items;
        _awaitingFirestoreIds =
            awaitingItems.map((i) => i.firestoreId ?? '').toSet()
              ..remove('');
        _loading = false;
      });
    }
  }

  bool _isAwaiting(PendingItem item) =>
      item.firestoreId != null &&
      _awaitingFirestoreIds.contains(item.firestoreId);

  Future<void> _markAwaiting(PendingItem item) async {
    await context
        .read<AppProvider>()
        .markItemAwaitingValidation(item.id!, firestoreId: item.firestoreId);
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
    final open =
        _items.where((p) => !p.isResolved && !_isAwaiting(p)).toList();
    final awaiting =
        _items.where((p) => !p.isResolved && _isAwaiting(p)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Text(c.local.isNotEmpty ? 'Stand ${c.local}' : c.displayName,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                          if (c.local.isNotEmpty)
                            _chip(Icons.grid_on, c.local),
                          if (c.area.isNotEmpty)
                            _chip(Icons.square_foot, '${c.area} m²'),
                          if (c.montagem.isNotEmpty)
                            _chip(Icons.business, c.montagem),
                        ]),
                      ],
                    ),
                  ),

                  // Team responsibles
                  const _SectionTitle(
                      text: 'RESPONSÁVEIS POR EQUIPE',
                      color: Colors.grey),
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
                              _RespChip('Produtor', c.produtor,
                                  Colors.indigo),
                            if (c.marceneiro.isNotEmpty)
                              _RespChip('Marcenaria', c.marceneiro,
                                  Colors.brown),
                            if (c.tapeceiro.isNotEmpty)
                              _RespChip(
                                  'Tapeçaria', c.tapeceiro, Colors.purple),
                            if (c.eletricista.isNotEmpty)
                              _RespChip(
                                  'Elétrica', c.eletricista, Colors.orange),
                            if (c.faxineira.isNotEmpty)
                              _RespChip('Limpeza', c.faxineira,
                                  Colors.cyan.shade700),
                            _RespChip(
                                'Vidraceiro', 'Rodrigo', Colors.lightBlue),
                            _RespChip(
                                'Com. Visual', 'Vinícius', Colors.pink),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Project link
                  if (c.projectLink.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () async {
                            String target = c.projectLink.trim();
                            if (!target.startsWith('http://') && !target.startsWith('https://')) {
                              target = 'https://$target';
                            }
                            final uri = Uri.tryParse(target);
                            if (uri == null) return;
                            try {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Não foi possível abrir o link.')));
                              }
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                const Icon(Icons.folder_open,
                                    color: Color(0xFF1E3A5F), size: 20),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text('Abrir projeto no Drive',
                                      style: TextStyle(
                                          color: Color(0xFF1E3A5F),
                                          fontWeight: FontWeight.w600)),
                                ),
                                const Icon(Icons.open_in_new,
                                    size: 16, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],

                  if (c.linkCv.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: InkWell(
                        onTap: () async {
                          String target = c.linkCv.trim();
                          if (!target.startsWith('http://') && !target.startsWith('https://')) {
                            target = 'https://$target';
                          }
                          final uri = Uri.tryParse(target);
                          if (uri == null) return;
                          try {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Não foi possível abrir o link.')));
                            }
                          }
                        },
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

                  // Open pending items
                  if (open.isNotEmpty) ...[
                    _SectionTitle(
                        text: 'PENDÊNCIAS ABERTAS (${open.length})',
                        color: Colors.orange),
                    ...open.map((item) => _PendingCard(
                          item: item,
                          isAwaiting: false,
                          onConcluir: () => _markAwaiting(item),
                          onCopy: () => _copyWhatsApp(item),
                        )),
                  ],

                  // Awaiting validation items
                  if (awaiting.isNotEmpty) ...[
                    _SectionTitle(
                        text:
                            'AGUARDANDO VALIDAÇÃO (${awaiting.length})',
                        color: Colors.blue),
                    ...awaiting.map((item) => _PendingCard(
                          item: item,
                          isAwaiting: true,
                          onConcluir: null,
                          onCopy: () => _copyWhatsApp(item),
                        )),
                  ],

                  if (_items.where((p) => !p.isResolved).isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 48, color: Colors.green),
                            SizedBox(height: 8),
                            Text('Nenhuma pendência aberta!',
                                style: TextStyle(
                                    color: Colors.green, fontSize: 15)),
                          ],
                        ),
                      ),
                    ),

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
              style:
                  const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );
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
            Text(person, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}

class _PendingCard extends StatelessWidget {
  final PendingItem item;
  final bool isAwaiting;
  final VoidCallback? onConcluir;
  final VoidCallback onCopy;

  const _PendingCard({
    required this.item,
    required this.isAwaiting,
    required this.onConcluir,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isAwaiting
        ? Colors.blue.shade200
        : Colors.orange.shade200;
    final bgColor = isAwaiting ? Colors.blue.shade50 : Colors.white;

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
              _TeamBadge(team: item.team),
              if (item.responsible.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(item.responsible,
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 12)),
              ],
              const Spacer(),
              if (isAwaiting)
                const Row(children: [
                  Icon(Icons.schedule, color: Colors.blue, size: 14),
                  SizedBox(width: 4),
                  Text('Aguardando validação',
                      style: TextStyle(
                          color: Colors.blue,
                          fontSize: 11,
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
            Text(item.description,
                style: const TextStyle(fontSize: 14)),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
              if (onConcluir != null) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onConcluir,
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Concluir',
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
