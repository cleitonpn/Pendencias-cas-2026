import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/client.dart';
import '../widgets/spec_block.dart';
import '../models/pending_item.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../services/cloud_writes.dart';
import '../widgets/resolution_dialog.dart';
import '../widgets/pending_status.dart';
import '../widgets/photo_gallery.dart';
import '../widgets/montage_section.dart';
import '../widgets/client_specs_card.dart';
import '../widgets/analyst_notes_widget.dart';
import 'add_pending_screen.dart';

class ProducerClientDetailScreen extends StatefulWidget {
  final Client client;
  final String producerName;
  const ProducerClientDetailScreen(
      {super.key, required this.client, this.producerName = ''});

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
        widget.client.rowId, excludeUnapproved: true);
    final awaitingItems = await FirestoreService.getAwaitingItemsByClientId(
        widget.client.firestoreId);
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
      item.awaitingValidation ||
      (item.firestoreId != null &&
          _awaitingFirestoreIds.contains(item.firestoreId));

  Future<void> _toggleComplete() async {
    final newVal = !widget.client.isCompleted;
    await context.read<AppProvider>().markClientCompleted(widget.client, newVal);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newVal
              ? 'Stand marcado como concluído!'
              : 'Stand reaberto.'),
          backgroundColor: newVal ? Colors.green : Colors.orange));
    }
  }

  Future<void> _addPending() async {
    final added = await Navigator.push<PendingItem>(
      context,
      MaterialPageRoute(
        builder: (_) => AddPendingScreen(
          client: widget.client,
          createdBy: widget.producerName.isNotEmpty
              ? 'Produtor: ${widget.producerName}'
              : 'Produtor',
        ),
      ),
    );
    if (added != null) await _load();
  }

  Future<void> _markInProgress(PendingItem item) async {
    final name = widget.producerName.isNotEmpty ? widget.producerName : 'Produtor';
    if (item.id != null) {
      await DatabaseService.markInProgress(item.id!, name);
    }
    if (item.firestoreId != null) {
      await FirestoreService.markInProgress(item.firestoreId!, name);
    }
    await _load();
  }

  Future<void> _markAwaiting(PendingItem item) async {
    final r = await showResolutionDialog(
      context,
      fairId: context.read<AppProvider>().currentFair?.id ?? 1,
      title: 'Marcar como concluída?',
      message: 'A pendência irá para validação do administrador. Você pode '
          'registrar uma nota de manutenção e fotos do serviço — ambos '
          'opcionais e visíveis para a organizadora e o expositor.',
      confirmLabel: 'Confirmar',
    );
    if (r == null || !mounted) return;
    // Nota e fotos ficam gravadas já na conclusão do produtor, antes da
    // validação, para não se perderem no caminho.
    if (r.note.isNotEmpty || r.photoUrls.isNotEmpty) {
      if (item.id != null) {
        await DatabaseService.setResolutionNote(item.id!,
            note: r.note, photoUrls: r.photoUrls);
      }
      if (item.firestoreId != null && item.firestoreId!.isNotEmpty) {
        final fid = item.firestoreId!;
        CloudWrites.fireAndForget(
          'nota de manutenção (${item.clientName})',
          () => FirestoreService.setResolutionNote(fid,
              note: r.note, photoUrls: r.photoUrls),
        );
      }
    }
    if (item.id != null) {
      await context.read<AppProvider>().markItemAwaitingValidation(
          item.id!,
          firestoreId: item.firestoreId);
    } else if (item.firestoreId != null) {
      await FirestoreService.markAwaitingValidation(item.firestoreId!);
    }
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
        backgroundColor: c.isCompleted ? Colors.green : const Color(0xFF1E3A5F),
        title: Text(c.local.isNotEmpty ? 'Stand ${c.local}' : c.displayName,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(
              c.isCompleted ? Icons.check_circle : Icons.check_circle_outline,
              color: c.isCompleted ? Colors.white : Colors.white,
            ),
            tooltip: c.isCompleted ? 'Reabrir Stand' : 'Concluir Stand',
            onPressed: _toggleComplete,
          ),
        ],
      ),
      // Compacto: o botão estendido cobria os botões de ação do último card
      // (Concluir/Peguei!) na lista de pendências.
      floatingActionButton: FloatingActionButton.small(
        onPressed: _addPending,
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        tooltip: 'Nova pendência',
        child: const Icon(Icons.add),
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
                            // A mestra já mostra o tipo no lugar da montagem; repetir
                            // a mesma informação duas vezes só ocuparia espaço.
                            if (c.tipo.isNotEmpty && c.tipo != c.montagem)
                              _chip(Icons.category_outlined, c.tipo),
                        ]),
                      ],
                    ),
                  ),

                  // Completed banner
                  if (c.isCompleted)
                    Container(
                      width: double.infinity,
                      color: Colors.green,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('✓ Stand concluído',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
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

                  if (c.linkCvEfetivo.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: InkWell(
                        onTap: () async {
                          String target = c.linkCvEfetivo.trim();
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

                  if (c.linkMemorial.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: InkWell(
                        onTap: () async {
                          String target = c.linkMemorial.trim();
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
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.teal.shade200),
                          ),
                          child: Row(children: [
                            Icon(Icons.description_outlined, color: Colors.teal.shade700, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Ver Memorial Descritivo',
                                style: TextStyle(
                                    color: Colors.teal.shade700,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14),
                              ),
                            ),
                            Icon(Icons.open_in_new, color: Colors.teal.shade400, size: 16),
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

                  // Extras
                  if (c.extras.isNotEmpty) ...[
                    const _SectionTitle(
                        text: 'EXTRAS', color: Colors.deepPurple),
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
                              const Icon(Icons.star_outline,
                                  color: Colors.deepPurple, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(c.extras,
                                    style: const TextStyle(fontSize: 14)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Balcões e cores, vindos da planilha.
                  ClientSpecExtras(client: c),

                  // Stand specifications (filled by consultant, read-only)
                  ClientSpecsCard(clientId: c.firestoreId, legacyClientId: c.rowId),

                  // Analyst notes (read-only for producer)
                  AnalystNotesWidget(clientId: c.firestoreId, canEdit: false),

                  // Montage progress photos (producer can add)
                  MontageSection(
                    clientId: c.firestoreId,
                    fairId: c.fairId,
                    fairName:
                        context.read<AppProvider>().currentFairName,
                    canAdd: true,
                    createdBy: widget.producerName.isNotEmpty
                        ? widget.producerName
                        : 'Produtor',
                  ),

                  // Open pending items
                  if (open.isNotEmpty) ...[
                    _SectionTitle(
                        text: 'PENDÊNCIAS ABERTAS (${open.length})',
                        color: Colors.orange),
                    ...open.map((item) => _PendingCard(
                          item: item,
                          isAwaiting: false,
                          onInProgress: item.inProgress
                              ? null
                              : () => _markInProgress(item),
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
                          onInProgress: null,
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

                  // Espaço para o FAB não encobrir o último card.
                  const SizedBox(height: 88),
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
  final VoidCallback? onInProgress;
  final VoidCallback? onConcluir;
  final VoidCallback onCopy;

  const _PendingCard({
    required this.item,
    required this.isAwaiting,
    required this.onInProgress,
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
                ])
              else if (item.inProgress && item.inProgressBy.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.deepPurple.shade200),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.engineering, color: Colors.deepPurple.shade600, size: 13),
                    const SizedBox(width: 4),
                    Text('Em andamento por ${item.inProgressBy}',
                        style: TextStyle(
                            color: Colors.deepPurple.shade600,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ]),
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
            Text(item.description,
                style: const TextStyle(fontSize: 14)),
            PendingNotes(item: item, showHistory: true),
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
            Wrap(spacing: 8, runSpacing: 6, children: [
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
              if (onInProgress != null)
                OutlinedButton.icon(
                  onPressed: onInProgress,
                  icon: const Icon(Icons.engineering, size: 14),
                  label: const Text('Peguei!',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.deepPurple,
                    side: const BorderSide(color: Colors.deepPurple),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                ),
              if (onConcluir != null)
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
