import 'dart:convert';

/// Um item de mobiliário, do jeito que ele aparece na planilha.
class FurnitureItem {
  /// O texto como está na coluna: "4 cadeiras dkr", "10m linear jardim".
  ///
  /// É este texto que vai impresso na OS. A quantidade já está nele, e
  /// tentar recompor a partir do número separado é onde a informação se
  /// perde: "10m" não é dez unidades.
  final String raw;

  /// Quantidade, quando o item começa com um número inteiro simples. Null em
  /// "10m linear jardim" ou em item sem número. Serve só para contagem, nunca
  /// para o que é mostrado.
  final int? qtd;

  /// Identidade do item dentro do stand.
  ///
  /// Vem do texto, não da posição. Guardar "o 3º item é externo" faria toda
  /// classificação escorregar uma casa quando alguém inserisse uma linha no
  /// meio da planilha — e em silêncio. Pelo texto, mexer no item faz ele
  /// aparecer como NÃO classificado, que é um erro que se vê.
  final String key;

  const FurnitureItem({
    required this.raw,
    required this.key,
    this.qtd,
  });

  /// Verdadeiro quando a quebra parece suspeita e vale conferir a planilha.
  ///
  /// Não bloqueia nada: só marca na tela para a equipe olhar. A barra é
  /// confiável no dia a dia, mas erro de digitação existe e é melhor
  /// aparecer antes de virar OS.
  bool get suspeito => raw.length > 60 || raw.length < 3;

  @override
  String toString() => raw;
}

/// Quebra a coluna de mobiliário nos itens que a compõem.
///
/// O padrão da planilha é uma barra entre itens:
///   "4 cadeiras dkr / 1 mesa dkr / 1 geladeira"
List<FurnitureItem> furnitureItemsFrom(String coluna) {
  final vistos = <String, int>{};
  final out = <FurnitureItem>[];

  for (final parte in coluna.split('/')) {
    // Espaço duplo e sobras aparecem na planilha real; sem normalizar, o
    // mesmo item viraria duas chaves diferentes entre uma leitura e outra.
    final raw = parte.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (raw.isEmpty) continue;

    var key = furnitureKey(raw);
    // Dois itens escritos igual no mesmo stand ("1 cadeira / 1 cadeira") são
    // duas linhas de verdade e precisam de chaves distintas, senão
    // classificar uma classificaria a outra.
    final repeticao = (vistos[key] ?? 0) + 1;
    vistos[key] = repeticao;
    if (repeticao > 1) key = '$key#$repeticao';

    out.add(FurnitureItem(raw: raw, key: key, qtd: _qtdDe(raw)));
  }
  return out;
}

/// Identidade do item a partir do texto: minúsculas, sem acento e sem
/// pontuação, para diferença de digitação não criar item novo.
String furnitureKey(String raw) {
  var s = raw.toLowerCase().trim();
  const acentos = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'ê': 'e', 'è': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };
  acentos.forEach((k, v) => s = s.split(k).join(v));
  return s.replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

/// Número inteiro no começo do item, quando existe e está isolado.
///
/// "4 cadeiras" → 4. "10m linear" → null, porque 10 é medida e não contagem;
/// somar isso com unidades daria um total sem significado.
int? _qtdDe(String raw) {
  final m = RegExp(r'^(\d+)\s').firstMatch(raw);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// Onde cada item é atendido.
///
/// [naoMobiliario] existe porque a coluna às vezes recebe uma observação que
/// não é item nenhum. Sem essa saída, aquela linha ficaria para sempre na
/// fila de classificação e a feira nunca apareceria como concluída.
enum FurnitureKind { interno, externo, naoMobiliario }

extension FurnitureKindLabel on FurnitureKind {
  String get label => switch (this) {
        FurnitureKind.interno => 'Interno',
        FurnitureKind.externo => 'Externo',
        FurnitureKind.naoMobiliario => 'Não é mobiliário',
      };

  String get code => switch (this) {
        FurnitureKind.interno => 'interno',
        FurnitureKind.externo => 'externo',
        FurnitureKind.naoMobiliario => 'nao_mobiliario',
      };

  /// Entra em OS e em pendência de mobiliário. O descartado fica de fora dos
  /// dois: não é item para ninguém atender.
  bool get atendivel => this != FurnitureKind.naoMobiliario;
}

FurnitureKind? furnitureKindFrom(Object? v) => switch (v) {
      'interno' => FurnitureKind.interno,
      'externo' => FurnitureKind.externo,
      'nao_mobiliario' => FurnitureKind.naoMobiliario,
      _ => null,
    };

/// Um item marcado numa pendência de mobiliário.
///
/// Guarda o texto do item E a classificação que ele tinha NA HORA do chamado.
/// Ler a classificação atual na hora do relatório daria um número errado: se
/// um item passar de interno para externo depois, todo problema antigo dele
/// mudaria de lado no histórico. A pergunta que o relatório responde é "onde
/// deu problema", e isso é o que valia quando o problema aconteceu.
class FurniturePick {
  /// Identidade do item dentro do stand (mesma chave de [FurnitureItem]).
  final String key;

  /// O texto do item como estava na planilha quando o chamado foi aberto.
  ///
  /// Fica gravado junto porque a linha pode ser corrigida ou apagada depois, e
  /// sem o texto a pendência antiga viraria uma chave sem significado.
  final String raw;

  /// Classificação no momento do chamado. Null quando o item ainda não tinha
  /// sido classificado pela equipe de mobiliário — não é "interno por padrão".
  final FurnitureKind? kind;

  const FurniturePick({required this.key, required this.raw, this.kind});

  Map<String, dynamic> toMap() => {
        'key': key,
        'raw': raw,
        if (kind != null) 'kind': kind!.code,
      };

  factory FurniturePick.fromMap(Map<dynamic, dynamic> m) => FurniturePick(
        key: (m['key'] ?? '').toString(),
        raw: (m['raw'] ?? '').toString(),
        kind: furnitureKindFrom(m['kind']),
      );

  /// Rótulo curto para a tela: "Interno", "Externo" ou "Sem classificação".
  String get kindLabel => kind?.label ?? 'Sem classificação';
}

/// Lê a lista gravada, venha ela do Firestore (List) ou do SQLite (JSON).
///
/// Tolerante de propósito: um chamado com a lista corrompida ainda precisa
/// abrir, mostrando a descrição — perder o chamado inteiro por causa dos itens
/// seria pior do que perder os itens.
List<FurniturePick> furniturePicksFrom(Object? raw) {
  if (raw == null) return const [];
  Object? valor = raw;
  if (valor is String) {
    final s = valor.trim();
    if (s.isEmpty) return const [];
    try {
      valor = jsonDecode(s);
    } catch (_) {
      return const [];
    }
  }
  if (valor is! List) return const [];
  return valor
      .whereType<Map>()
      .map(FurniturePick.fromMap)
      .where((p) => p.raw.isNotEmpty)
      .toList();
}
