import 'package:flutter/material.dart';
import '../services/update_service.dart';
import '../utils/apk_installer.dart';
import '../utils/apk_progress.dart';

/// Shows the "new version available" prompt and, if accepted, the download
/// progress while the APK is fetched and the installer is launched.
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
          const Text('Há uma atualização disponível do app. Deseja baixar e '
              'instalar agora?'),
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

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DownloadDialog(url: info.apkUrl),
  );
}

class _DownloadDialog extends StatefulWidget {
  final String url;
  const _DownloadDialog({required this.url});

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  int _percent = 0;
  String _status = 'Iniciando download...';
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    try {
      installApk(widget.url).listen((e) {
        if (!mounted) return;
        setState(() {
          if (e.percent >= 0) _percent = e.percent;
          if (e.isError) {
            _error = true;
            _status = 'Falha ao baixar. Tente novamente.';
          } else if (e.status == 'INSTALLING') {
            _status = 'Abrindo instalador...';
          } else {
            _status = 'Baixando atualização...';
          }
        });
      }, onError: (_) {
        if (mounted) {
          setState(() {
            _error = true;
            _status = 'Falha ao baixar. Tente novamente.';
          });
        }
      });
    } catch (_) {
      setState(() {
        _error = true;
        _status = 'Não foi possível iniciar a atualização.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Atualizando'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_error) ...[
            LinearProgressIndicator(
              value: _percent > 0 ? _percent / 100 : null,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
            ),
            const SizedBox(height: 12),
            Text('$_status${_percent > 0 ? " ($_percent%)" : ""}',
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ] else ...[
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text(_status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: _error
          ? [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar')),
            ]
          : [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Continuar em segundo plano')),
            ],
    );
  }
}
