import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pending_item.dart';
import '../providers/app_provider.dart';
import '../services/firestore_service.dart';
import '../widgets/photo_gallery.dart';

/// Consultant / admin queue of all organizer requests awaiting approval.
/// Uses a Firestore stream so no fair needs to be "selected" first.
/// Approve/reject call Firestore directly (items from the stream have no
/// local SQLite id); SQLite is updated as a side-effect via the pending stream.
class OrganizerApprovalScreen extends StatelessWidget {
  final String approverName;
  const OrganizerApprovalScreen({super.key, this.approverName = ''});

  // Keep backwards compat with callers that pass consultantName.
  // ignore: non_constant_identifier_names
  static OrganizerApprovalScreen withConsultant(String name) =>
      OrganizerApprovalScreen(approverName: name);

  String get _by =>
      approverName.isNotEmpty ? approverName : 'Atendimento';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Pedidos da Organizadora',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<List<PendingItem>>(
        stream: FirestoreService.streamAllPendingApprovals(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text('Erro: ${snap.error}',
                  style: const TextStyle(color: Colors.red)),
            );
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Nenhum pedido aguardando aprovação.',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, i) => _ApprovalCard(
              item: items[i],
              onApprove: () => _approve(context, items[i]),
              onReject: () => _reject(context, items[i]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _approve(BuildContext context, PendingItem item) async {
    final fid = item.firestoreId ?? '';
    if (fid.isEmpty) return;

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
    if (ok != true || !context.mounted) return;

    try {
      // Always update Firestore first — the stream will remove the item automatically.
      await FirestoreService.approveOrganizerItem(fid);
      // Also sync to local SQLite if the item exists there.
      if (item.id != null) {
        await context.read<AppProvider>().approveOrganizerItem(
              item.id!,
              firestoreId: fid,
            );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Pedido aprovado e liberado.'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro ao aprovar: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _reject(BuildContext context, PendingItem item) async {
    final fid = item.firestoreId ?? '';
    if (fid.isEmpty) return;

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
                'O pedido será finalizado. A organizadora verá o motivo (opcional).',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Motivo da recusa (opcional)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
    if (ok != true || !context.mounted) return;

    try {
      await FirestoreService.rejectOrganizerItem(fid,
          reason: ctrl.text.trim(), by: _by);
      if (item.id != null) {
        await context.read<AppProvider>().rejectOrganizerItem(
              item.id!,
              firestoreId: fid,
              reason: ctrl.text.trim(),
              by: _by,
            );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Pedido recusado.'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro ao recusar: $e'),
            backgroundColor: Colors.red));
      }
    }
  }
}

// ─── Card ─────────────────────────────────────────────────────────────────────

class _ApprovalCard extends StatelessWidget {
  final PendingItem item;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
  });

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
            // Fair label
            if (item.fairName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.event_outlined,
                      size: 13, color: Color(0xFF1E3A5F)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(item.fairName,
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF1E3A5F),
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            // Organizer badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.badge_outlined,
                    size: 13, color: Colors.purple),
                const SizedBox(width: 4),
                Text(
                    item.createdBy.isNotEmpty
                        ? item.createdBy
                        : 'Organizadora',
                    style: const TextStyle(
                        color: Colors.purple,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Text(
                  '${item.hangar.isNotEmpty ? "Hangar ${item.hangar} • " : ""}Stand ${item.local}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              Text(item.team,
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
            if (item.clientName.isNotEmpty)
              Text(item.clientName,
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 12)),
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

// ─── Reusable banner widget ───────────────────────────────────────────────────

/// Banner shown on list screens (consultant home, admin fair selection).
/// Shows pending organizer approval count live and opens OrganizerApprovalScreen.
class OrganizerApprovalBanner extends StatelessWidget {
  final String approverName;
  const OrganizerApprovalBanner({super.key, this.approverName = ''});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PendingItem>>(
      stream: FirestoreService.streamAllPendingApprovals(),
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        if (count == 0 && snap.connectionState != ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        return GestureDetector(
          onTap: count == 0
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          OrganizerApprovalScreen(approverName: approverName),
                    ),
                  ),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: count > 0
                  ? Colors.orange.shade50
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: count > 0
                      ? Colors.orange.shade300
                      : Colors.grey.shade300,
                  width: 1.5),
            ),
            child: Row(
              children: [
                Icon(Icons.fact_check_outlined,
                    color: count > 0
                        ? Colors.orange.shade800
                        : Colors.grey,
                    size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: snap.connectionState == ConnectionState.waiting
                      ? const Text(
                          'Verificando pedidos da organizadora…',
                          style:
                              TextStyle(color: Colors.grey, fontSize: 13))
                      : Text(
                          count == 0
                              ? 'Nenhum pedido aguardando aprovação'
                              : count == 1
                                  ? '1 pedido da organizadora aguardando aprovação'
                                  : '$count pedidos da organizadora aguardando aprovação',
                          style: TextStyle(
                              color: count > 0
                                  ? Colors.orange.shade900
                                  : Colors.grey,
                              fontWeight: count > 0
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              fontSize: 13),
                        ),
                ),
                if (count > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade800,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$count',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right,
                      color: Colors.orange.shade800, size: 20),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
