import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// Miniatura de uma foto recém-escolhida, antes do upload.
///
/// `Image.file` depende de `dart:io` e não compila para web; no navegador o
/// `XFile.path` é uma blob URL, não um caminho de arquivo. Ler os bytes
/// funciona nas duas plataformas — é o mesmo caminho já usado no upload.
class LocalImagePreview extends StatelessWidget {
  final XFile file;
  final double size;

  const LocalImagePreview({super.key, required this.file, this.size = 84});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: file.readAsBytes(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            width: size,
            height: size,
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Image.memory(
          snap.data!,
          width: size,
          height: size,
          fit: BoxFit.cover,
        );
      },
    );
  }
}
