import 'package:flutter/material.dart';
import '../models/client.dart';

/// Um campo da ficha do stand: título, ícone e o texto vindo da planilha.
///
/// Some quando o campo está vazio — nem todo stand tem balcão ou cor
/// definida, e uma seção vazia só ocupa espaço na tela de quem está em pé no
/// pavilhão.
class SpecBlock extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final String text;

  const SpecBlock({
    super.key,
    required this.title,
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 1)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(text, style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Balcão padrão, balcão personalizado e cores.
///
/// Ficam juntos num widget só para entrarem iguais em todas as telas de ficha
/// — admin, consultor, produtor e analista. Repetir os três blocos em cada
/// tela abriria espaço para eles divergirem com o tempo.
class ClientSpecExtras extends StatelessWidget {
  final Client client;
  const ClientSpecExtras({super.key, required this.client});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SpecBlock(
            title: 'BALCÃO PADRÃO',
            color: const Color(0xFF00796B),
            icon: Icons.countertops_outlined,
            text: client.balcaoPadrao,
          ),
          SpecBlock(
            title: 'BALCÃO PERSONALIZADO',
            color: const Color(0xFF5D4037),
            icon: Icons.design_services_outlined,
            text: client.balcaoPersonalizado,
          ),
          SpecBlock(
            title: 'CORES',
            color: const Color(0xFFC2185B),
            icon: Icons.palette_outlined,
            text: client.cores,
          ),
        ],
      );
}
