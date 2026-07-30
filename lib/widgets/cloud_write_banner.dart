import 'package:flutter/material.dart';
import '../services/cloud_writes.dart';

/// Envolve o app inteiro e mostra a faixa de "não salvo na nuvem" quando há
/// algo pendente.
///
/// Fica acima do Navigator porque a gravação que falhou pode ter partido de
/// qualquer tela, e o aviso precisa alcançar o usuário onde ele estiver.
///
/// Enquanto a faixa aparece, o recorte do topo é removido do que está abaixo:
/// sem isso a barra de status seria contada duas vezes — uma pela faixa,
/// outra pela AppBar de cada tela — e tudo desceria.
class CloudWriteScope extends StatelessWidget {
  final Widget child;
  const CloudWriteScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CloudWrites.failureCount,
      builder: (context, count, _) {
        if (count == 0) return child;
        return Column(
          children: [
            const CloudWriteBanner(),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Faixa que aparece quando alguma alteração não chegou à nuvem.
///
/// O app grava primeiro no aparelho e só depois manda para a nuvem, para que
/// trabalhar sem sinal continue funcionando. O efeito colateral era que uma
/// gravação recusada — permissão, documento apagado, dado inválido — sumia
/// sem deixar rastro: a tela mostrava a alteração salva e ela nunca existia
/// para os outros. Esta faixa é o rastro.
class CloudWriteBanner extends StatelessWidget {
  const CloudWriteBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CloudWrites.failureCount,
      builder: (context, count, _) {
        if (count == 0) return const SizedBox.shrink();
        return SafeArea(
          bottom: false,
          child: Material(
          color: const Color(0xFFFFF3E0),
          child: InkWell(
            onTap: () => _detalhes(context),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off,
                      size: 18, color: Color(0xFFE65100)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      count == 1
                          ? '1 alteração não foi salva na nuvem'
                          : '$count alterações não foram salvas na nuvem',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFE65100),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Text('Ver',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFE65100),
                          fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _detalhes(BuildContext context) async {
    final falhas = CloudWrites.failures;
    final messenger = ScaffoldMessenger.of(context);

    final tentar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.cloud_off, color: Color(0xFFE65100)),
          SizedBox(width: 8),
          Expanded(child: Text('Não salvo na nuvem')),
        ]),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Estas alterações estão salvas neste aparelho, mas ainda não '
                'chegaram aos outros:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView(
                  shrinkWrap: true,
                  children: falhas
                      .map((f) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('• ${f.what}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                Text(
                                  _motivo(f.error),
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Fechar')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.refresh, size: 18),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white),
            label: const Text('Tentar de novo'),
          ),
        ],
      ),
    );

    if (tentar != true) return;
    final restantes = await CloudWrites.retryAll();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: restantes == 0 ? Colors.green : Colors.red,
        content: Text(restantes == 0
            ? 'Tudo salvo na nuvem.'
            : '$restantes ainda não subiram. Confira a conexão.'),
      ),
    );
  }

  /// Traduz o erro para algo que ajude a decidir o que fazer.
  static String _motivo(Object e) {
    final texto = e.toString().toLowerCase();
    if (texto.contains('permission') || texto.contains('permission-denied')) {
      return 'Permissão negada — o app pode estar desatualizado.';
    }
    if (texto.contains('not-found')) {
      return 'O registro não existe mais na nuvem.';
    }
    if (texto.contains('unavailable') || texto.contains('network')) {
      return 'Sem conexão com o servidor.';
    }
    return 'Falha ao gravar.';
  }
}
