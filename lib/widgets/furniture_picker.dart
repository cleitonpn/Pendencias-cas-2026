import 'package:flutter/material.dart';
import '../models/client.dart';
import '../services/firestore_service.dart';
import '../utils/furniture_items.dart';

/// Marca QUAL móvel do stand está com problema, ao abrir uma pendência de
/// mobiliário.
///
/// Digitar o item à mão gera "cadeira dkr", "Cadeira DKR" e "a cadeira preta"
/// para a mesma coisa — e depois não dá para contar nada. Marcando na lista do
/// próprio stand, o chamado já nasce sabendo o item e o lado (interno ou
/// sublocado).
///
/// A lista vem da planilha; a classificação vem da equipe de mobiliário. Item
/// ainda não classificado APARECE do mesmo jeito: o problema do expositor não
/// espera a classificação ficar pronta.
///
/// Nada aqui bloqueia o chamado. A planilha pode estar atrasada, e por isso
/// existe a opção "não está na lista" — um chamado sem item é muito melhor do
/// que um chamado que não foi aberto.
class FurniturePicker extends StatefulWidget {
  final Client client;

  /// Chaves marcadas agora. O pai é o dono do estado porque é ele quem salva.
  final Set<String> selected;

  /// Marcou "não está na lista".
  final bool outro;

  final ValueChanged<Set<String>> onChanged;
  final ValueChanged<bool> onOutroChanged;

  /// Cor da equipe de mobiliário, para a seleção combinar com o cartão dela.
  final Color color;

  /// Mostrar o selo Interno/Externo em cada item.
  ///
  /// Falso nos portais do expositor e da organizadora: para eles a cadeira é
  /// só a cadeira. Interno x externo é divisão de trabalho nossa — quem está
  /// de fora não tem como agir sobre isso, e ver "Externo" só levanta a
  /// pergunta de por que aquilo importa.
  final bool mostrarClassificacao;

  const FurniturePicker({
    super.key,
    required this.client,
    required this.selected,
    required this.outro,
    required this.onChanged,
    required this.onOutroChanged,
    this.color = const Color(0xFF00796B),
    this.mostrarClassificacao = true,
  });

  /// Os itens que podem ser marcados num stand, já sem os descartados.
  ///
  /// Quem classificou como "não é mobiliário" disse que aquela linha é uma
  /// observação, não um móvel. Oferecer para marcar traria de volta o texto que
  /// a equipe acabou de tirar da frente.
  static List<FurnitureItem> itensDe(
      Client client, Map<String, String> classificacao) {
    return furnitureItemsFrom(client.mobilario)
        .where((i) =>
            furnitureKindFrom(classificacao[i.key]) !=
            FurnitureKind.naoMobiliario)
        .toList();
  }

  @override
  State<FurniturePicker> createState() => _FurniturePickerState();
}

class _FurniturePickerState extends State<FurniturePicker> {
  Map<String, String> _kinds = const {};
  List<FurnitureItem> _itens = const [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    var kinds = <String, String>{};
    try {
      kinds = await FirestoreService.getFurnitureKinds(
          widget.client.firestoreId);
    } catch (_) {
      // Sem a classificação a lista ainda serve: os itens aparecem como "sem
      // classificação" e o chamado sai. Ficar sem a lista por causa disso
      // devolveria o problema da digitação livre.
    }
    if (!mounted) return;
    setState(() {
      _kinds = kinds;
      _itens = FurniturePicker.itensDe(widget.client, kinds);
      _carregando = false;
    });
  }

  void _alternar(FurnitureItem item) {
    final novo = Set<String>.from(widget.selected);
    if (!novo.remove(item.key)) novo.add(item.key);
    widget.onChanged(novo);
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Row(children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Carregando o mobiliário do stand...',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('QUAL MOBILIÁRIO?',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1)),
        const SizedBox(height: 6),
        Text(
          _itens.isEmpty
              ? 'Este stand não tem itens lançados na planilha.'
              : 'Marque o item com problema — pode marcar mais de um.',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        ..._itens.map(_linha),
        _linhaOutro(),
      ],
    );
  }

  Widget _linha(FurnitureItem item) {
    final marcado = widget.selected.contains(item.key);
    final kind = furnitureKindFrom(_kinds[item.key]);
    return InkWell(
      onTap: () => _alternar(item),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: marcado ? widget.color.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: marcado ? widget.color : Colors.grey.shade300,
            width: marcado ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Icon(marcado ? Icons.check_box : Icons.check_box_outline_blank,
              color: marcado ? widget.color : Colors.grey, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.raw,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            marcado ? FontWeight.w600 : FontWeight.normal,
                        color: marcado ? widget.color : Colors.black87)),
                if (widget.mostrarClassificacao) ...[
                  const SizedBox(height: 2),
                  _selo(kind),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _selo(FurnitureKind? kind) {
    final texto = kind?.label ?? 'Sem classificação';
    final cor = switch (kind) {
      FurnitureKind.interno => const Color(0xFF00796B),
      FurnitureKind.externo => const Color(0xFFE65100),
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(texto,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: cor)),
    );
  }

  /// Saída para quando a planilha está atrasada ou o item não foi lançado.
  Widget _linhaOutro() {
    return InkWell(
      onTap: () => widget.onOutroChanged(!widget.outro),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: widget.outro ? Colors.grey.shade200 : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.outro ? Colors.grey.shade600 : Colors.grey.shade300,
            width: widget.outro ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Icon(
              widget.outro
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              color: widget.outro ? Colors.grey.shade700 : Colors.grey,
              size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _itens.isEmpty
                  ? 'Descrever na mensagem'
                  : 'Não está na lista / outro item',
              style: TextStyle(
                  fontSize: 14,
                  color: widget.outro
                      ? Colors.grey.shade800
                      : Colors.black87),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Os itens marcados, já com a classificação congelada no momento do chamado.
///
/// Fica fora do widget para a tela poder montá-los na hora de salvar sem
/// depender do estado da tela.
Future<List<FurniturePick>> furniturePicksFor({
  required Client client,
  required Set<String> selected,
}) async {
  if (selected.isEmpty) return const [];
  var kinds = <String, String>{};
  try {
    kinds = await FirestoreService.getFurnitureKinds(client.firestoreId);
  } catch (_) {
    // Sem classificação os itens entram como "sem classificação" — o que é a
    // verdade, e melhor do que perder o item marcado.
  }
  return furnitureItemsFrom(client.mobilario)
      .where((i) => selected.contains(i.key))
      .map((i) => FurniturePick(
            key: i.key,
            raw: i.raw,
            kind: furnitureKindFrom(kinds[i.key]),
          ))
      .toList();
}
