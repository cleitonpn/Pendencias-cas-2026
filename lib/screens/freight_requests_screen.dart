import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/freight_request.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

class FreightRequestsScreen extends StatelessWidget {
  final int fairId;
  final String fairName;
  final String viewerRole;
  final String viewerName;

  const FreightRequestsScreen({
    super.key,
    required this.fairId,
    required this.fairName,
    required this.viewerRole,
    required this.viewerName,
  });

  @override
  Widget build(BuildContext context) {
    final isLogistics = viewerRole == 'logistica';
    final canDelete = viewerRole == 'admin' || viewerRole == 'manager';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fairId < 0 ? 'Todas as Feiras' : fairName,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const Text('Solicitações de Logística',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<List<FreightRequest>>(
        stream: FirestoreService.streamFreightRequests(fairId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Erro: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red)));
          }
          final requests = snapshot.data ?? [];

          if (requests.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_shipping_outlined,
                      size: 72, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Nenhuma solicitação',
                      style: TextStyle(color: Colors.grey, fontSize: 18)),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (isLogistics) _DashboardRow(requests: requests),
              if (isLogistics) const SizedBox(height: 16),
              ...requests.map((r) => _RequestCard(
                    request: r,
                    isLogistics: isLogistics,
                    canDelete: canDelete,
                    viewerName: viewerName,
                  )),
            ],
          );
        },
      ),
    );
  }
}

class _DashboardRow extends StatelessWidget {
  final List<FreightRequest> requests;
  const _DashboardRow({required this.requests});

  @override
  Widget build(BuildContext context) {
    final emAberto = requests.where((r) => r.isOpen).length;
    final agendado = requests.where((r) => r.isScheduled).length;
    final despachado = requests.where((r) => r.isDispatched).length;
    final finalizado = requests.where((r) => r.isFinalized).length;

    return Row(
      children: [
        _Counter(label: 'Em aberto', count: emAberto, color: Colors.red),
        _Counter(label: 'Agendado', count: agendado, color: Colors.blue),
        _Counter(label: 'Despachado', count: despachado, color: Colors.orange),
        _Counter(label: 'Finalizado', count: finalizado, color: Colors.green),
      ],
    );
  }
}

class _Counter extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _Counter(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Text('$count',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  final FreightRequest request;
  final bool isLogistics;
  final bool canDelete;
  final String viewerName;

  const _RequestCard({
    required this.request,
    required this.isLogistics,
    required this.canDelete,
    required this.viewerName,
  });

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _loading = false;

  static const _motivoLabels = {
    'montagem': 'Montagem',
    'desmontagem': 'Desmontagem',
    'sobra': 'Sobra',
    'extra': 'Extra',
    'itens_faltantes': 'Itens Faltantes',
    'outros': 'Outros',
  };

  static const _equipeLabels = {
    'marcenaria': 'Marcenaria',
    'tapecaria': 'Tapeçaria',
    'eletrica': 'Elétrica',
    'comunicacao_visual': 'Comuni. Visual',
    'vidracaria': 'Vidraçaria',
    'outros': 'Outros',
  };

  String _fmtIso(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  Future<void> _acceptRequest() async {
    final noteCtrl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Aceitar solicitação'),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Observação (opcional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, noteCtrl.text),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (note == null || !mounted) return;
    setState(() => _loading = true);
    try {
      await FirestoreService.updateFreightRequestStatus(
        widget.request.id!,
        'agendado',
        widget.viewerName,
        note: note,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _dispatchRequest() async {
    setState(() => _loading = true);
    try {
      await FirestoreService.updateFreightRequestStatus(
        widget.request.id!,
        'despachado',
        widget.viewerName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmReceipt() async {
    final picker = ImagePicker();
    XFile? photo;

    final takePhoto = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Confirmar Recebimento'),
        content: const Text(
            'Deseja adicionar uma foto de comprovante? (opcional)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Sem foto')),
          ElevatedButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text('Tirar Foto'),
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
    if (takePhoto == null || !mounted) return;

    if (takePhoto) {
      try {
        photo = await picker.pickImage(
            source: ImageSource.camera, imageQuality: 70);
      } catch (_) {
        try {
          photo = await picker.pickImage(
              source: ImageSource.gallery, imageQuality: 70);
        } catch (_) {}
      }
    }

    setState(() => _loading = true);
    try {
      String photoUrl = '';
      if (photo != null) {
        photoUrl = await StorageService.uploadReceiptPhoto(
          requestId: widget.request.id!,
          file: photo,
        );
      }
      await FirestoreService.updateFreightRequestStatus(
        widget.request.id!,
        'finalizado',
        widget.viewerName,
        photoUrl: photoUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Recebimento confirmado!'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteRequest() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Excluir solicitação?'),
        content: Text(
            'Excluir solicitação #${widget.request.number} de ${widget.request.requestedBy}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FirestoreService.deleteFreightRequest(widget.request.id!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: r.statusColor.withOpacity(0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A5F),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('#${r.number}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
                const SizedBox(width: 8),
                if (r.isUrgent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('URGENTE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                const Spacer(),
                // Status chip
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: r.statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: r.statusColor, width: 1),
                  ),
                  child: Text(r.statusLabel,
                      style: TextStyle(
                          color: r.statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
                if (widget.canDelete && r.isOpen) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 20),
                    tooltip: 'Excluir',
                    onPressed: _loading ? null : _deleteRequest,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Fair name (if showing all fairs)
            if (r.fairName.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.event, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(r.fairName,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12)),
                ],
              ),

            // Stands
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.store, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      r.clientNames.isEmpty
                          ? 'Toda a feira'
                          : r.clientNames.join(', '),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

            // Portão
            if (r.portao.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.door_front_door_outlined,
                        size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(r.portao,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87)),
                  ],
                ),
              ),

            // Items
            if (r.items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  r.items,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),

            // Motivos chips
            if (r.motivos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: r.motivos.map((m) {
                    return Chip(
                      label: Text(_motivoLabels[m] ?? m,
                          style: const TextStyle(fontSize: 11)),
                      backgroundColor: Colors.purple.shade50,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    );
                  }).toList(),
                ),
              ),

            // Equipes chips
            if (r.equipes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: r.equipes.map((e) {
                    return Chip(
                      label: Text(_equipeLabels[e] ?? e,
                          style: const TextStyle(fontSize: 11)),
                      backgroundColor: Colors.blue.shade50,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    );
                  }).toList(),
                ),
              ),

            // Scheduled for
            if (r.scheduledFor.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text('Previsto: ${_fmtIso(r.scheduledFor)}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),

            // Requester
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('Por: ${r.requestedBy}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),

            // HandledBy (for logistics view)
            if (widget.isLogistics && r.handledBy.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    const Icon(Icons.engineering_outlined,
                        size: 14, color: Colors.blueGrey),
                    const SizedBox(width: 4),
                    Text('Responsável: ${r.handledBy}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.blueGrey)),
                  ],
                ),
              ),

            // Status note
            if (r.statusNote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.notes, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                        child: Text(r.statusNote,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey))),
                  ],
                ),
              ),

            // Action buttons
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Center(
                    child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else ...[
              // Logistics: accept
              if (widget.isLogistics && r.isOpen) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Aceitar → Agendado'),
                    onPressed: _acceptRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],

              // Logistics: dispatch
              if (widget.isLogistics && r.isScheduled) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.local_shipping, size: 18),
                    label: const Text('Despachar → Despachado'),
                    onPressed: _dispatchRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],

              // Requester: confirm receipt
              if (!widget.isLogistics &&
                  r.isDispatched &&
                  widget.viewerName == r.requestedBy) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.task_alt, size: 18),
                    label: const Text('Confirmar Recebimento'),
                    onPressed: _confirmReceipt,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
