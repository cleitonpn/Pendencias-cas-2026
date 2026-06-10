import 'package:flutter/material.dart';
import '../models/pending_item.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../widgets/photo_gallery.dart';
import 'package:provider/provider.dart';

/// Attendant (consultant) queue of organizer requests awaiting approval.
/// Approve → the request becomes a normal pending and flows to producer/leader.
/// Reject → the request is finalized with a reason the organizer can see.
class OrganizerApprovalScreen extends StatefulWidget {
  final String consultantName;
  const OrganizerApprovalScreen({super.key, this.consultantName = ''});

  @override
  State<OrganizerApprovalScreen> createState() =>
      _OrganizerApprovalScreenState();
}

class _OrganizerApprovalScreenState extends State<OrganizerApprovalScreen> {
  List<PendingItem> _items = [];
  bool _loading = false;
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
    if (!silent) setState(() => _loading = true);
    final fairId = context.read<AppProvider>().currentFair?.id ?? 1;
    final items = await DatabaseService.getPendingApprovalItems(fairId: fairId);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  String get _by => widget.consultantName.isNotEmpty
      ? 'Consultor: ${widget.consultantName}'
      : 'Atendimento';

  Future<void> _approve(PendingItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Aprovar pedido?'),
        content: const Text(
            'A pendência será liberada para o produtor e o líder da equipe.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await context
        .read<AppProvider>()
        .approveOrganizerItem(item.id!, firestoreId: item.firestoreId);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pedido aprovado e liberado.'),
          backgroundColor: Colors.green));
    }
  }

  Future<void> _reject(PendingItem item) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Recusar pedido?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'O pedido será finalizado. A organizadora verá o motivo abaixo (opcional).',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Motivo da recusa (opcional)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Recusar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppProvider>().rejectOrganizerItem(
          item.id!,
          firestoreId: item.firestoreId,
          reason: ctrl.text.trim(),
          by: _by,
        );
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pedido recusado.'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Pedidos da Organizadora',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('Nenhum pedido aguardando aprovação.',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (context, i) => _ApprovalCard(
                    item: _items[i],
                    onApprove: () => _approve(_items[i]),
                    onReject: () => _reject(_items[i]),
                  ),
                ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final PendingItem item;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalCard(
      {required this.item, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.badge_outlined,
                    size: 13, color: Colors.purple),
                const SizedBox(width: 4),
                Text(item.createdBy.isNotEmpty ? item.createdBy : 'Organizadora',
                    style: const TextStyle(
                        color: Colors.purple,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Text('${item.hangar.isNotEmpty ? "Hangar ${item.hangar} • " : ""}Stand ${item.local}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              Text(item.team,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
            if (item.clientName.isNotEmpty)
              Text(item.clientName,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            Text(item.description, style: const TextStyle(fontSize: 14)),
            if (item.photoUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              PhotoStrip(urls: item.photoUrls),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Recusar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Aprovar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
