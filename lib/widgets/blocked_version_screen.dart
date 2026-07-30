import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';
import '../services/version_gate.dart';

/// Tela que substitui o app quando a versão instalada é antiga demais.
///
/// Não tem "agora não". Uma versão abaixo da mínima não funciona pela metade:
/// ela bate em permissão negada no Firestore e mostra mensagens que não fazem
/// sentido para quem está em campo. Parar aqui, dizendo o que fazer, é melhor
/// do que deixar a pessoa brigando com um app quebrado.
class BlockedVersionScreen extends StatefulWidget {
  final VersionVerdict verdict;
  const BlockedVersionScreen({super.key, required this.verdict});

  @override
  State<BlockedVersionScreen> createState() => _BlockedVersionScreenState();
}

class _BlockedVersionScreenState extends State<BlockedVersionScreen> {
  static const _navy = Color(0xFF1E3A5F);
  String? _apkUrl;
  bool _procurando = true;

  @override
  void initState() {
    super.initState();
    _buscarApk();
  }

  Future<void> _buscarApk() async {
    final info = await UpdateService.checkForUpdate();
    if (mounted) {
      setState(() {
        _apkUrl = info?.apkUrl;
        _procurando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.verdict;
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.system_update, size: 80, color: _navy),
                const SizedBox(height: 20),
                const Text(
                  'Atualização obrigatória',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: _navy),
                ),
                const SizedBox(height: 12),
                Text(
                  v.message.isNotEmpty
                      ? v.message
                      : 'Esta versão do app não funciona mais. Atualize para '
                          'continuar usando.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Colors.black87),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Instalada: ${v.localBuild}  ·  Mínima: ${v.minBuild}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 28),
                if (kIsWeb)
                  // Na web a versão antiga vem do cache do navegador; recarregar
                  // sem cache resolve.
                  const Text(
                    'Feche esta aba e abra o link de novo. Se continuar '
                    'aparecendo, atualize a página segurando o botão de '
                    'recarregar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  )
                else if (_procurando)
                  const CircularProgressIndicator()
                else if (_apkUrl != null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.download),
                      label: const Text('Baixar nova versão'),
                      onPressed: () => launchUrl(
                        Uri.parse(_apkUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  )
                else
                  const Text(
                    'Não foi possível encontrar o download automaticamente. '
                    'Peça o APK mais recente à coordenação.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _procurando ? null : _buscarApk,
                  child: const Text('Tentar de novo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
