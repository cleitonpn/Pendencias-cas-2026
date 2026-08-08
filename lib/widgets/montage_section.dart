import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../models/montage_update.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

/// Montage progress section for a client/stand. The producer sends photos with
/// the camera ("Atualização da montagem") and everyone sees the timeline of
/// how the stand evolved (most recent first).
class MontageSection extends StatefulWidget {
  final String clientId;
  final int fairId;
  final String fairName;
  final bool canAdd;     // producer can add; others only view
  final String createdBy;

  const MontageSection({
    super.key,
    required this.clientId,
    required this.fairId,
    required this.fairName,
    this.canAdd = false,
    this.createdBy = '',
  });

  @override
  State<MontageSection> createState() => _MontageSectionState();
}

class _MontageSectionState extends State<MontageSection> {
  final _picker = ImagePicker();
  List<MontageUpdate> _updates = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await FirestoreService.getMontageUpdates(widget.clientId);
      if (mounted) setState(() { _updates = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPhoto() async {
    try {
      final shot = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
      if (shot == null) return;
      setState(() => _sending = true);
      final url = await StorageService.uploadPendingPhoto(
        fairId: widget.fairId,
        file: shot,
        index: 0,
      );
      await FirestoreService.saveMontageUpdate(
        clientId: widget.clientId,
        fairName: widget.fairName,
        photoUrl: url,
        createdBy: widget.createdBy,
      );
      // Mostra na hora (otimista) e recarrega do servidor.
      if (mounted) {
        setState(() {
          _updates.insert(
            0,
            MontageUpdate(
              id: 'local',
              clientId: widget.clientId,
              fairName: widget.fairName,
              photoUrl: url,
              createdBy: widget.createdBy,
              createdAt: DateTime.now(),
            ),
          );
          _sending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Atualização enviada!'),
            backgroundColor: Colors.green));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível enviar a foto. Tente novamente.'),
            backgroundColor: Colors.red));
      }
    }
  }

  void _openPhoto(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.network(
                  url,
                  errorBuilder: (c, e, s) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.image_not_supported_outlined,
                            color: Colors.white54, size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'Não foi possível exibir a foto aqui.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Abrir no navegador'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            const Icon(Icons.photo_camera_outlined,
                size: 16, color: Color(0xFF1E3A5F)),
            const SizedBox(width: 6),
            Text('ATUALIZAÇÃO DA MONTAGEM (${_updates.length})',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E3A5F),
                    letterSpacing: 1)),
          ]),
        ),
        if (widget.canAdd)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _addPhoto,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.photo_camera),
                label: Text(_sending ? 'Enviando...' : 'Atualização da montagem'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_updates.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nenhuma foto de montagem ainda.',
                style: TextStyle(color: Colors.grey)),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: _updates.map((u) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10)),
                        child: GestureDetector(
                          onTap: () => _openPhoto(u.photoUrl),
                          child: Image.network(
                            u.photoUrl,
                            width: double.infinity,
                            height: 180,
                            fit: BoxFit.cover,
                            loadingBuilder: (c, w, p) => p == null
                                ? w
                                : Container(
                                    height: 180,
                                    color: Colors.grey.shade100,
                                    child: const Center(
                                        child: CircularProgressIndicator())),
                            // Quando a imagem não carrega, o ícone quebrado
                            // sozinho não diz nada e não deixa saída. Abrir no
                            // navegador funciona mesmo quando a exibição
                            // dentro da página é bloqueada, então serve de
                            // saída para o usuário e de pista para nós.
                            errorBuilder: (c, e, s) => InkWell(
                              onTap: () => launchUrl(
                                Uri.parse(u.photoUrl),
                                mode: LaunchMode.externalApplication,
                              ),
                              child: Container(
                                height: 180,
                                color: Colors.grey.shade100,
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.image_not_supported_outlined,
                                        color: Colors.grey, size: 32),
                                    SizedBox(height: 8),
                                    Text('Não foi possível exibir a foto aqui',
                                        style: TextStyle(
                                            fontSize: 12, color: Colors.grey)),
                                    SizedBox(height: 2),
                                    Text('Toque para abrir no navegador',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF1E3A5F),
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(children: [
                          const Icon(Icons.schedule,
                              size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(_fmt(u.createdAt),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                          if (u.createdBy.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('• ${u.createdBy}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ]),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
