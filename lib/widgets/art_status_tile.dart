import 'package:flutter/material.dart';
import '../models/client.dart';

/// A faixa de status da arte na ficha do stand.
///
/// Some quando não há informação, e isso é deliberado: um stand que ainda não
/// foi importado para a ferramenta de aprovação não tem status nenhum, e
/// mostrar "sem informação" em metade das fichas treinaria todo mundo a
/// ignorar o campo — inclusive nas fichas em que ele diz algo.
///
/// A cor é a mensagem. Vermelho é o que trava a montagem; verde é o que já
/// pode sair da cabeça de quem está no galpão.
class ArtStatusTile extends StatelessWidget {
  final Client client;

  const ArtStatusTile({super.key, required this.client});

  @override
  Widget build(BuildContext context) {
    final arte = client.arte;
    if (arte == null) return const SizedBox.shrink();

    final cor = arte.cor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cor.withOpacity(0.45)),
        ),
        child: Row(
          children: [
            Icon(arte.icone, color: cor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comunicação visual: ${arte.rotulo}',
                    style: TextStyle(
                      color: cor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (arte.contador.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        arte.contador,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
