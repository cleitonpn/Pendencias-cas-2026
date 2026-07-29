import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/stand_storage.dart';

/// O que o usuário informou ao concluir (ou aprovar) um chamado.
/// Ambos os campos são opcionais.
class ResolutionResult {
  final String note;
  final List<String> photoUrls;

  const ResolutionResult({this.note = '', this.photoUrls = const []});
}

/// Diálogo de conclusão com nota de manutenção e fotos do serviço — os dois
/// opcionais. Retorna `null` se o usuário cancelar, e um [ResolutionResult]
/// (possivelmente vazio) se confirmar.
///
/// [fairId] é usado apenas para organizar o caminho no Storage.
Future<ResolutionResult?> showResolutionDialog(
  BuildContext context, {
  required int fairId,
  String title = 'Concluir pendência?',
  String message =
      'Você pode registrar uma nota de manutenção e fotos do serviço. '
      'Ambos são opcionais.',
  String confirmLabel = 'Concluir',
  Color confirmColor = Colors.green,
  bool allowPhotos = true,
}) {
  return showDialog<ResolutionResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ResolutionDialog(
      fairId: fairId,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      confirmColor: confirmColor,
      allowPhotos: allowPhotos,
    ),
  );
}

class _ResolutionDialog extends StatefulWidget {
  final int fairId;
  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;
  final bool allowPhotos;

  const _ResolutionDialog({
    required this.fairId,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
    required this.allowPhotos,
  });

  @override
  State<_ResolutionDialog> createState() => _ResolutionDialogState();
}

class _ResolutionDialogState extends State<_ResolutionDialog> {
  final _noteCtrl = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _photos = [];
  bool _saving = false;
  String? _uploadError;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final shot =
            await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1600);
        if (shot != null) setState(() => _photos.add(shot));
      } else {
        final picked =
            await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1600);
        if (picked.isNotEmpty) setState(() => _photos.addAll(picked));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _uploadError = 'Não foi possível abrir as fotos.');
      }
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _saving = true;
      _uploadError = null;
    });

    final urls = <String>[];
    try {
      for (var i = 0; i < _photos.length; i++) {
        final bytes = await _photos[i].readAsBytes();
        urls.add(await StandStorage.uploadPhotoBytes(
          fairId: widget.fairId,
          bytes: bytes,
          index: i,
        ));
      }
    } catch (_) {
      // A conclusão não pode ficar travada por falha de upload: avisa e deixa
      // o usuário concluir sem as fotos.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _uploadError =
            'Falha ao enviar as fotos. Você pode concluir sem elas ou tentar de novo.';
        _photos.clear();
      });
      return;
    }

    if (!mounted) return;
    Navigator.pop(
        context, ResolutionResult(note: _noteCtrl.text.trim(), photoUrls: urls));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(widget.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.message,
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 14),
              TextField(
                controller: _noteCtrl,
                enabled: !_saving,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Nota da montadora (opcional)',
                  hintText: 'Ex.: painel realinhado e parafusos trocados.',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              if (widget.allowPhotos) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _saving ? null : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera, size: 18),
                      label: const Text('Câmera',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _saving ? null : () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library, size: 18),
                      label: const Text('Galeria',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ]),
                if (_photos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(_photos.length, (i) {
                      return Chip(
                        avatar: const Icon(Icons.image, size: 16),
                        label: Text('Foto ${i + 1}',
                            style: const TextStyle(fontSize: 12)),
                        onDeleted:
                            _saving ? null : () => setState(() => _photos.removeAt(i)),
                      );
                    }),
                  ),
                ],
              ],
              if (_uploadError != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(_uploadError!,
                      style:
                          const TextStyle(color: Colors.red, fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.confirmColor,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(widget.confirmLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
