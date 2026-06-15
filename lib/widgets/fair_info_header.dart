import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/client.dart';

/// Displays pavilhão, assembly/event/teardown dates and a floor-plan link
/// read from the first client in the fair (all clients share these fair-level
/// values). Hidden when no client data is available.
class FairInfoHeader extends StatelessWidget {
  final List<Client> clients;
  final bool showDriveLink;
  const FairInfoHeader(
      {super.key, required this.clients, this.showDriveLink = false});

  @override
  Widget build(BuildContext context) {
    if (clients.isEmpty) return const SizedBox.shrink();

    final c = clients.first;
    final hasDates = c.dataMontagem.isNotEmpty ||
        c.dataEvento.isNotEmpty ||
        c.dataDesmontagem.isNotEmpty;
    final hasPavilhao = c.pavilhao.isNotEmpty;
    final hasPlanta = c.linkPlanta.isNotEmpty;
    final hasDrive = showDriveLink && c.linkDrive.isNotEmpty;

    if (!hasDates && !hasPavilhao && !hasPlanta && !hasDrive) return const SizedBox.shrink();

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
          if (hasPlanta || hasDrive) ...[
            if (hasDates || hasPavilhao) const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (hasPlanta)
                  _LinkButton(
                    icon: Icons.map_outlined,
                    label: 'Ver planta do evento',
                    color: Colors.teal,
                    url: c.linkPlanta,
                    onTap: (url) => _launch(context, url),
                  ),
                if (hasDrive)
                  _LinkButton(
                    icon: Icons.folder_open_outlined,
                    label: 'Abrir pasta do Drive',
                    color: Colors.indigo,
                    url: c.linkDrive,
                    onTap: (url) => _launch(context, url),
                  ),
              ],
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

class _LinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final MaterialColor color;
  final String url;
  final void Function(String) onTap;
  const _LinkButton(
      {required this.icon,
      required this.label,
      required this.color,
      required this.url,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(url),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.shade200),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color.shade700, size: 15),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Icon(Icons.open_in_new, color: color.shade400, size: 12),
        ]),
      ),
    );
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
