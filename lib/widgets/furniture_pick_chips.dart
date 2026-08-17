import 'package:flutter/material.dart';
import '../utils/furniture_items.dart';

/// Os móveis marcados num chamado de mobiliário.
///
/// Aparece junto da descrição porque é a primeira coisa que quem vai atender
/// precisa saber: qual item levar e de que lado ele é. A cor separa o que é do
/// estoque (interno) do que é sublocado (externo) — quem sublocou precisa
/// acionar fornecedor, e isso muda o tempo de resposta.
///
/// Mostra a classificação GRAVADA no chamado, não a atual. Se o item mudar de
/// lado depois, este chamado continua contando a história de quando aconteceu.
class FurniturePickChips extends StatelessWidget {
  final List<FurniturePick> items;

  /// Compacto para lista de cartões; solto para a tela de detalhe.
  final bool dense;

  const FurniturePickChips({
    super.key,
    required this.items,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: dense ? 4 : 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: items.map(_chip).toList(),
      ),
    );
  }

  Widget _chip(FurniturePick p) {
    final cor = switch (p.kind) {
      FurnitureKind.interno => const Color(0xFF00796B),
      FurnitureKind.externo => const Color(0xFFE65100),
      _ => Colors.grey.shade600,
    };
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 6 : 8, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cor.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chair_alt, size: dense ? 12 : 14, color: cor),
          const SizedBox(width: 4),
          Text(p.raw,
              style: TextStyle(
                  fontSize: dense ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: cor)),
          const SizedBox(width: 5),
          Text(p.kindLabel,
              style: TextStyle(
                  fontSize: dense ? 9 : 10,
                  color: cor.withOpacity(0.75))),
        ],
      ),
    );
  }
}
