import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/app_provider.dart';
import '../models/client.dart';
import '../models/pending_item.dart';
import '../services/storage_service.dart';
import '../widgets/local_image_preview.dart';

/// Edits team, responsible, description and photos of an unresolved pending item.
class EditPendingScreen extends StatefulWidget {
  final PendingItem item;
  final Client client;
  const EditPendingScreen(
      {super.key, required this.item, required this.client});

  @override
  State<EditPendingScreen> createState() => _EditPendingScreenState();
}

class _EditPendingScreenState extends State<EditPendingScreen> {
  static const _teams = [
    'Limpeza',
    'Elétrica',
    'Marcenaria',
    'Tapeçaria',
    'Vidraceiro',
    'Comunicação Visual',
  ];

  late String _selectedTeam;
  late final TextEditingController _responsibleCtrl;
  late final TextEditingController _descCtrl;
  late List<String> _existingPhotos;
  final List<XFile> _newPhotos = [];
  final _picker = ImagePicker();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedTeam = _teams.contains(widget.item.team)
        ? widget.item.team
        : _teams.first;
    _responsibleCtrl =
        TextEditingController(text: widget.item.responsible);
    _descCtrl =
        TextEditingController(text: widget.item.description);
    _existingPhotos = List<String>.from(widget.item.photoUrls);
  }

  @override
  void dispose() {
    _responsibleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String _defaultResponsible(String team) {
    final c = widget.client;
    switch (team) {
      case 'Limpeza':            return c.faxineira;
      case 'Elétrica':           return c.eletricista;
      case 'Marcenaria':         return c.marceneiro;
      case 'Tapeçaria':          return c.tapeceiro;
      case 'Vidraceiro':         return 'Rodrigo';
      case 'Comunicação Visual': return 'Vinícius';
      default:                   return '';
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final picked =
            await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1600);
        if (picked.isNotEmpty) setState(() => _newPhotos.addAll(picked));
      } else {
        final picked = await _picker.pickImage(
            source: source, imageQuality: 70, maxWidth: 1600);
        if (picked != null) setState(() => _newPhotos.add(picked));
      }
    } catch (_) {
      _snack('Não foi possível selecionar a foto.', isError: true);
    }
  }

  Future<void> _save() async {
    if (_descCtrl.text.trim().isEmpty) {
      _snack('A descrição não pode ficar vazia.', isError: true);
      return;
    }
    if (widget.item.id == null) {
      _snack('Esta pendência não pode ser editada.', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final urls = List<String>.from(_existingPhotos);
      if (_newPhotos.isNotEmpty) {
        final uploaded = await StorageService.uploadPendingPhotos(
          fairId: widget.client.fairId,
          files: _newPhotos,
        );
        urls.addAll(uploaded);
      }
      await context.read<AppProvider>().editPendingItemFull(
            widget.item.id!,
            firestoreId: widget.item.firestoreId,
            team: _selectedTeam,
            responsible: _responsibleCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            photoUrls: urls,
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Falha ao salvar. Verifique a conexão e tente novamente.',
            isError: true);
      }
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Editar Pendência',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stand info (read-only)
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: const Icon(Icons.store_outlined,
                    color: Color(0xFF1E3A5F)),
                title: Text(widget.client.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    'Stand ${widget.client.local}'
                    '${widget.client.hangar.isNotEmpty ? " • Hangar ${widget.client.hangar}" : ""}'),
              ),
            ),
            const SizedBox(height: 20),

            // Team dropdown
            _label('EQUIPE'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedTeam,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.groups_outlined,
                    color: Color(0xFF1E3A5F)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
              ),
              items: _teams
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() {
                        _selectedTeam = v;
                        // Auto-fill responsible from client data; admin can override.
                        final def = _defaultResponsible(v);
                        if (def.isNotEmpty) _responsibleCtrl.text = def;
                      });
                    },
            ),
            const SizedBox(height: 16),

            // Responsible
            _label('RESPONSÁVEL'),
            const SizedBox(height: 8),
            TextField(
              controller: _responsibleCtrl,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.person_outline,
                    color: Color(0xFF1E3A5F)),
                hintText: 'Nome do responsável',
              ),
            ),
            const SizedBox(height: 16),

            // Description
            _label('DESCRIÇÃO'),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              enabled: !_saving,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // Photos
            _label('FOTOS'),
            const SizedBox(height: 8),
            if (_existingPhotos.isNotEmpty) ...[
              const Text('Atuais (toque no × para remover):',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 6),
              _photoRow(
                count: _existingPhotos.length,
                imageBuilder: (i) => Image.network(_existingPhotos[i],
                    width: 84, height: 84, fit: BoxFit.cover),
                onRemove: (i) =>
                    setState(() => _existingPhotos.removeAt(i)),
              ),
              const SizedBox(height: 12),
            ],
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _saving ? null : () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Câmera'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1E3A5F),
                    side: const BorderSide(color: Color(0xFF1E3A5F)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _saving ? null : () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Galeria'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1E3A5F),
                    side: const BorderSide(color: Color(0xFF1E3A5F)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]),
            if (_newPhotos.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Novas:',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 6),
              _photoRow(
                count: _newPhotos.length,
                imageBuilder: (i) =>
                    LocalImagePreview(file: _newPhotos[i]),
                onRemove: (i) => setState(() => _newPhotos.removeAt(i)),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save),
                label: const Text('Salvar alterações',
                    style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            letterSpacing: 1),
      );

  Widget _photoRow({
    required int count,
    required Widget Function(int) imageBuilder,
    required void Function(int) onRemove,
  }) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageBuilder(i),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: () => onRemove(i),
              child: Container(
                decoration: const BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close,
                    color: Colors.white, size: 16),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
