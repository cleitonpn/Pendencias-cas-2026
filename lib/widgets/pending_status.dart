import 'package:flutter/material.dart';
import '../models/pending_item.dart';

/// Situação de uma pendência para exibição.
///
/// Recusar um chamado grava `is_resolved = 1` junto com
/// `approval_status = 'recusada'` (ver DatabaseService.rejectOrganizerItem),
/// então qualquer tela que olhasse só `isResolved` mostrava um chamado
/// recusado como "Resolvido". A ordem de avaliação aqui resolve isso: a
/// recusa é verificada antes da resolução.
class PendingStatus {
  final String label;
  final Color color;
  final IconData icon;

  const PendingStatus(this.label, this.color, this.icon);

  static const rejected =
      PendingStatus('Recusado', Color(0xFFD32F2F), Icons.cancel);
  static const pendingApproval = PendingStatus(
      'Aguardando aprovação', Color(0xFFF57C00), Icons.schedule);
  static const awaitingValidation = PendingStatus(
      'Aguardando validação', Color(0xFFEF6C00), Icons.hourglass_bottom);
  static const resolved =
      PendingStatus('Resolvido', Color(0xFF2E7D32), Icons.check_circle);
  static const open =
      PendingStatus('Pendente', Color(0xFFE64A19), Icons.error_outline);

  bool get isRejected => label == rejected.label;
}

/// Situação de exibição de uma pendência. A recusa tem precedência sobre a
/// resolução, pois um chamado recusado também vem marcado como resolvido.
PendingStatus statusOf(PendingItem item) {
  if (item.isRejected) return PendingStatus.rejected;
  if (item.isPendingApproval) return PendingStatus.pendingApproval;
  if (item.isResolved) return PendingStatus.resolved;
  if (item.awaitingValidation) return PendingStatus.awaitingValidation;
  return PendingStatus.open;
}

/// Selo compacto com ícone + texto da situação.
class PendingStatusBadge extends StatelessWidget {
  final PendingItem item;
  final double fontSize;

  const PendingStatusBadge({super.key, required this.item, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    final s = statusOf(item);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(s.icon, color: s.color, size: fontSize + 4),
      const SizedBox(width: 4),
      Text(s.label,
          style: TextStyle(
              color: s.color,
              fontSize: fontSize,
              fontWeight: FontWeight.bold)),
    ]);
  }
}

/// Caixa com o motivo da recusa. Vazia quando o item não foi recusado.
class RejectionReasonBox extends StatelessWidget {
  final PendingItem item;

  const RejectionReasonBox({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    if (!item.isRejected || item.rejectionReason.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, color: Colors.red, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Motivo: ${item.rejectionReason}',
              style: const TextStyle(color: Colors.red, fontSize: 11)),
        ),
      ]),
    );
  }
}
