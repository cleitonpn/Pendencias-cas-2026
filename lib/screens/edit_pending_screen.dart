import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/app_provider.dart';
import '../models/client.dart';
import '../models/pending_item.dart';
import '../services/storage_service.dart';

/// Edits the description and photos of an unresolved pending item.
class EditPendingScreen extends StatefulWidget {
  final PendingItem item;
  final Client client;
  const EditPendingScreen(
      {super.key, required this.item, required this.client});

  @override
  State<EditPendingScreen> createState() => _EditPendingScreenState();
}

class _EditPendingScreenState extends State<EditPendingScreen> {
  late final TextEditingController _descCtrl =
      TextEditingController(text: widget.item.description);
  late List<String> _existingPhotos = List<String>.from(widget.item.photoUrls);
  final List<XFile> _newPhotos = [];
  final _picker = ImagePicker();
  bool _saving = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
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
          files: _newPhotos.map((x) => File(x.path)).toList(),
        );
        urls.addAll(uploaded);
      }
      await context.read<AppProvider>().editPendingItem(
            widget.item.id!,
            firestoreId: widget.item.firestoreId,
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
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: const Icon(Icons.info_outline, color: Color(0xFF1E3A5F)),
                title: Text(widget.item.team,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(widget.client.displayName),
              ),
            ),
            const SizedBox(height: 20),
            const Text('DESCRIÇÃO',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
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
            const Text('FOTOS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 10),
            if (_existingPhotos.isNotEmpty) ...[
              const Text('Atuais (toque no × para remover):',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 6),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _existingPhotos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(_existingPhotos[i],
                          width: 84, height: 84, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _existingPhotos.removeAt(i)),
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
              ),
              const SizedBox(height: 12),
            ],
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _pickPhoto(ImageSource.camera),
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
                  onPressed: _saving ? null : () => _pickPhoto(ImageSource.gallery),
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
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _newPhotos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(_newPhotos[i].path),
                          width: 84, height: 84, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => setState(() => _newPhotos.removeAt(i)),
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
}
