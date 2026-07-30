import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';

/// Mostra tudo o que aconteceu com um chamado, do mais recente ao mais antigo.
///
/// Existe para responder "quem fez o quê e quando". Antes, quando a
/// organizadora dizia "abri às 9h e ninguém fez nada", a resposta dependia da
/// memória de quem estava lá.
Future<void> showPendingHistory(BuildContext context, String pendingId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _HistorySheet(pendingId: pendingId),
  );
}

class _HistorySheet extends StatelessWidget {
  final String pendingId;
  const _HistorySheet({required this.pendingId});

  static const _navy = Color(0xFF1E3A5F);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, color: _navy, size: 20),
                SizedBox(width: 8),
                Text('Histórico do chamado',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _navy)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: FirestoreService.getPendingHistory(pendingId),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return const _Vazio(
                    icone: Icons.cloud_off,
                    texto: 'Não foi possível carregar o histórico.\n'
                        'Confira a conexão.',
                  );
                }
                final linhas = snap.data ?? const [];
                if (linhas.isEmpty) {
                  return const _Vazio(
                    icone: Icons.history_toggle_off,
                    texto: 'Nenhuma alteração registrada.\n\n'
                        'O histórico começou a ser gravado a partir da '
                        'versão mais recente do app — chamados antigos não '
                        'têm registro.',
                  );
                }
                return ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: linhas.length,
                  separatorBuilder: (_, __) => const Divider(height: 20),
                  itemBuilder: (context, i) => _Entrada(linha: linhas[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Entrada extends StatelessWidget {
  final Map<String, dynamic> linha;
  const _Entrada({required this.linha});

  String get _quando {
    final dt = DateTime.tryParse((linha['at'] as String?) ?? '');
    if (dt == null) return '';
    return DateFormat("dd/MM 'às' HH:mm").format(dt.toLocal());
  }

  String get _quem {
    final nome = (linha['by'] as String?) ?? '';
    final papel = (linha['role'] as String?) ?? '';
    if (nome.isEmpty) return 'Autor não registrado';
    final rotulo = switch (papel) {
      'producer' => 'Produtor',
      'consultant' => 'Consultor',
      'leader' => 'Líder',
      'analyst' => 'Analista',
      'manager' => 'Gerente',
      'admin' => 'Admin',
      'logistica' => 'Logística',
      _ => '',
    };
    return rotulo.isEmpty ? nome : '$nome · $rotulo';
  }

  @override
  Widget build(BuildContext context) {
    final mudancas = (linha['changes'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.person_outline, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(
              child: Text(_quem,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            Text(_quando,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 6),
        ...mudancas.map((m) {
          final c = Map<String, dynamic>.from(m as Map);
          final de = (c['from'] as String?) ?? '';
          final para = (c['to'] as String?) ?? '';
          return Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 3),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                children: [
                  TextSpan(
                      text: '${c['label']}: ',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (de.isNotEmpty)
                    TextSpan(
                      text: '$de ',
                      style: const TextStyle(
                        color: Colors.grey,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  if (de.isNotEmpty)
                    const TextSpan(
                        text: '→ ', style: TextStyle(color: Colors.grey)),
                  TextSpan(text: para),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _Vazio extends StatelessWidget {
  final IconData icone;
  final String texto;
  const _Vazio({required this.icone, required this.texto});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(texto,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
      );
}
