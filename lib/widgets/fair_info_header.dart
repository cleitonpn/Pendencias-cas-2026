import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/client.dart';

/// Displays pavilhão, assembly/event/teardown dates and a floor-plan link
/// read from the first client in the fair (all clients share these fair-level
/// values). Hidden when no client data is available.
class FairInfoHeader extends StatelessWidget {
  final List<Client> clients;
  const FairInfoHeader({super.key, required this.clients});

  @override
  Widget build(BuildContext context) {
    if (clients.isEmpty) return const SizedBox.shrink();

    final c = clients.first;
    final hasDates = c.dataMontagem.isNotEmpty ||
        c.dataEvento.isNotEmpty ||
        c.dataDesmontagem.isNotEmpty;
    final hasPavilhao = c.pavilhao.isNotEmpty;
    final hasPlanta = c.linkPlanta.isNotEmpty;

    if (!hasDates && !hasPavilhao && !hasPlanta) return const SizedBox.shrink();

    return Container(
      color: const Color(0xFF1E3A5F).withOpacity(0.04),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPavilhao) ...[
            Row(children: [
              const Icon(Icons.location_city,
                  size: 14, color: Color(0xFF1E3A5F)),
              const SizedBox(width: 6),
              Text('Pavilhão: ${c.pavilhao}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E3A5F))),
            ]),
            if (hasDates || hasPlanta) const SizedBox(height: 6),
          ],
          if (hasDates)
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                if (c.dataMontagem.isNotEmpty)
                  _DateChip(
                      icon: Icons.build_outlined,
                      label: 'Montagem',
                      value: c.dataMontagem),
                if (c.dataEvento.isNotEmpty)
                  _DateChip(
                      icon: Icons.event,
                      label: 'Evento',
                      value: c.dataEvento),
                if (c.dataDesmontagem.isNotEmpty)
                  _DateChip(
                      icon: Icons.delete_sweep_outlined,
                      label: 'Desmontagem',
                      value: c.dataDesmontagem),
              ],
            ),
          if (hasPlanta) ...[
            if (hasDates || hasPavilhao) const SizedBox(height: 6),
            InkWell(
              onTap: () => _launch(context, c.linkPlanta),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.map_outlined,
                      color: Colors.teal.shade700, size: 15),
                  const SizedBox(width: 6),
                  Text('Ver planta do evento',
                      style: TextStyle(
                          color: Colors.teal.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new,
                      color: Colors.teal.shade400, size: 12),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _launch(BuildContext context, String url) async {
    String target = url.trim();
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
  }
}

class _DateChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DateChip(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: Colors.grey.shade600),
      const SizedBox(width: 4),
      Text('$label: ',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600)),
      Text(value,
          style: const TextStyle(fontSize: 12, color: Colors.black87)),
    ]);
  }
}
