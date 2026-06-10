import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';

/// Shows the "new version available" prompt. Accepting opens the APK download
/// through the system (browser / download manager), which reliably follows
/// GitHub's redirects. The user then taps the downloaded file to install
/// (over the current app, since it is signed with the same key).
Future<void> showUpdateFlow(BuildContext context, UpdateInfo info) async {
  final accept = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: [
        const Icon(Icons.system_update, color: Color(0xFF1E3A5F)),
        const SizedBox(width: 8),
        Expanded(child: Text('Nova versão ${info.versionName}')),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Há uma atualização disponível do app. Deseja baixar '
              'agora?'),
          if (info.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(info.notes,
                  style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Agora não')),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.download),
          label: const Text('Atualizar'),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white),
        ),
      ],
    ),
  );

  if (accept != true || !context.mounted) return;

  bool launched = false;
  try {
    launched = await launchUrl(
      Uri.parse(info.apkUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    launched = false;
  }

  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(launched ? 'Download iniciado' : 'Baixar atualização'),
      content: Text(
        launched
            ? 'Quando o download terminar, abra o arquivo "app-release.apk" '
                '(na barra de notificações ou na pasta Downloads) e toque em '
                'Instalar. Seus dados são mantidos.'
            : 'Não foi possível abrir o download automaticamente. Acesse o '
                'link abaixo no navegador para baixar a nova versão:\n\n'
                '${info.apkUrl}',
        style: const TextStyle(fontSize: 14),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Ok')),
      ],
    ),
  );
}
