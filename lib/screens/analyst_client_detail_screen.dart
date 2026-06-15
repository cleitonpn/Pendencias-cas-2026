import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/client.dart';
import '../services/firestore_service.dart';
import '../widgets/client_specs_card.dart';
import '../widgets/analyst_notes_widget.dart';
import '../widgets/photo_gallery.dart';

/// Read-only client view for the Analyst role.
/// Shows all info: specs, pending history, montage photos.
/// Can edit analyst notes. Cannot create pending or complete clients.
class AnalystClientDetailScreen extends StatefulWidget {
  final List<Client> clients;
  final String hangar;
  final String analystName;

  const AnalystClientDetailScreen({
    super.key,
    required this.clients,
    required this.hangar,
    required this.analystName,
  });

  @override
  State<AnalystClientDetailScreen> createState() =>
      _AnalystClientDetailScreenState();
}

class _AnalystClientDetailScreenState
    extends State<AnalystClientDetailScreen> {
  int _selectedIndex = 0;

  Client get _client => widget.clients[_selectedIndex];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: Text('Hangar ${widget.hangar}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          if (widget.clients.length > 1)
            Container(
              height: 48,
              color: const Color(0xFF1E3A5F).withOpacity(0.08),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                itemCount: widget.clients.length,
                itemBuilder: (context, i) {
                  final c = widget.clients[i];
                  final selected = i == _selectedIndex;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIndex = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF1E3A5F)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: selected
                                ? const Color(0xFF1E3A5F)
                                : Colors.grey.shade300),
                      ),
                      child: Text(
                        c.local.isNotEmpty ? c.local : c.displayName,
                        style: TextStyle(
                            color: selected ? Colors.white : Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  _buildLinks(),
                  ClientSpecsCard(clientId: _client.rowId),
                  AnalystNotesWidget(
                    clientId: _client.rowId,
                    canEdit: true,
                    editorName: widget.analystName,
                  ),
                  _buildMontagePhotos(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final c = _client;
    return Container(
      width: double.infinity,
      color: const Color(0xFF1E3A5F),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
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
            if (c.area.isNotEmpty) _chip(Icons.square_foot, '${c.area} m²'),
            if (c.montagem.isNotEmpty) _chip(Icons.business, c.montagem),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (c.produtor.isNotEmpty)
              _chip(Icons.badge_outlined, c.produtor),
            if (c.atendimento.isNotEmpty)
              _chip(Icons.support_agent_outlined, c.atendimento),
          ]),
        ],
      ),
    );
  }

  Widget _buildLinks() {
    final c = _client;
    return Column(
      children: [
        if (c.projectLink.isNotEmpty)
          _linkTile(Icons.link, 'Ver projeto no Drive', c.projectLink,
              Colors.blue),
        if (c.linkMemorial.isNotEmpty)
          _linkTile(Icons.description_outlined, 'Ver Memorial Descritivo',
              c.linkMemorial, Colors.teal),
        if (c.linkCv.isNotEmpty)
          _linkTile(Icons.image_outlined, 'Ver print Comunicação Visual',
              c.linkCv, Colors.pink),
      ],
    );
  }

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

  Widget _buildMontagePhotos() {
    return _MontageSection(clientId: _client.rowId);
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
}

class _MontageSection extends StatefulWidget {
  final String clientId;
  const _MontageSection({required this.clientId});

  @override
  State<_MontageSection> createState() => _MontageSectionState();
}

class _MontageSectionState extends State<_MontageSection> {
  List<dynamic> _updates = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    FirestoreService.getMontageUpdates(widget.clientId).then((list) {
      if (mounted) setState(() { _updates = list; _loaded = true; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('ATUALIZAÇÃO DA MONTAGEM (${_updates.length})',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1)),
        ),
        if (_updates.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Nenhuma foto de montagem ainda.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PhotoStrip(
              urls: _updates.map((u) => u.photoUrl as String).toList(),
            ),
          ),
      ],
    );
  }
}
