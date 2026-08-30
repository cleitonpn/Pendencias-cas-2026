/// Identidade de um expositor que NÃO depende da posição dele na planilha.
///
/// O `firestoreId` é `feira_<posição na aba>`. Inserir, apagar ou reordenar
/// uma linha reescreve o id de todo mundo abaixo, e cada cliente herda o id do
/// vizinho. O que estava gravado sob aquele id — check-off, considerações,
/// especificações, classificação de mobiliário, prova de arte — passa a ser
/// mostrado no stand errado. Não some: troca de dono, em silêncio, e parece
/// certo.
///
/// A chave daqui vem do nome da feira e do nome do expositor, que é a
/// identidade que as duas bases têm em comum.
///
/// ## Contrato com a ferramenta de aprovação de arte
///
/// Esta normalização tem de ser IDÊNTICA dos dois lados, caractere por
/// caractere. A implementação de referência em JavaScript está em
/// `tools/client_key_parity.test.js`, que roda no CI deste repositório com os
/// mesmos casos testados aqui em Dart — o mesmo arranjo que já existe para o
/// sanitizador de tópicos FCM.
///
/// O ponto onde é fácil errar: acento não é REMOVIDO, é CONVERTIDO. "Módulos"
/// vira `modulos`, não `mdulos`. (O `_normalize` antigo de `sheets_service`,
/// usado no `firestoreId`, apaga o caractere acentuado — por isso ele não
/// serve como chave compartilhada.)
library;

const _acentos = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'ê': 'e', 'è': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

/// Uma parte da chave: minúsculas, sem acento, e tudo que não é letra ou
/// número vira um `_` só.
///
/// Nunca começa nem termina com `_`, e nunca contém `__` — é isso que faz o
/// separador de [clientKeyFor] ser inequívoco.
String normalizeKeyPart(String raw) {
  var s = raw.toLowerCase().trim();
  _acentos.forEach((k, v) => s = s.replaceAll(k, v));
  return s
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

/// Separador entre feira e expositor. Duplo de propósito: nenhuma parte
/// normalizada contém `__`, então a chave nunca é ambígua — "feira_a" +
/// "b" não pode colidir com "feira" + "a_b".
const kClientKeySeparator = '__';

/// A chave estável de um expositor, ou vazio quando não dá para formar uma.
///
/// Devolve vazio quando falta o nome da feira ou o do expositor. Chave pela
/// metade ligaria coisas que não têm relação nenhuma.
String clientKeyFor({required String fairName, required String nome}) {
  final f = normalizeKeyPart(fairName);
  final n = normalizeKeyPart(nome);
  if (f.isEmpty || n.isEmpty) return '';
  return '$f$kClientKeySeparator$n';
}

/// As chaves de uma feira inteira, com as ambíguas descartadas.
///
/// Dois expositores com o mesmo nome na mesma feira dariam a mesma chave.
/// Nenhum dos dois recebe chave: eles ficam sem prova de arte até alguém
/// desfazer a ambiguidade na planilha, e é isso que se quer. Desempatar pela
/// posição resolveria na aparência e traria de volta, pela porta dos fundos, o
/// problema que a chave existe para eliminar — só que agora invisível.
///
/// [nomes] são os nomes dos expositores da feira, na ordem que vierem.
/// Devolve nome normalizado → chave, sem as chaves em disputa.
Map<String, String> clientKeysFor(String fairName, Iterable<String> nomes) {
  final contagem = <String, int>{};
  for (final n in nomes) {
    final k = normalizeKeyPart(n);
    if (k.isEmpty) continue;
    contagem[k] = (contagem[k] ?? 0) + 1;
  }
  return {
    for (final e in contagem.entries)
      if (e.value == 1) e.key: clientKeyFor(fairName: fairName, nome: e.key),
  };
}

/// Os nomes que aparecem mais de uma vez numa feira, já normalizados.
///
/// Serve para a equipe saber quais stands ficaram sem chave e por quê, em vez
/// de descobrir pela ausência de prova de arte.
List<String> nomesAmbiguos(Iterable<String> nomes) {
  final contagem = <String, int>{};
  for (final n in nomes) {
    final k = normalizeKeyPart(n);
    if (k.isEmpty) continue;
    contagem[k] = (contagem[k] ?? 0) + 1;
  }
  final dup = contagem.entries.where((e) => e.value > 1).map((e) => e.key).toList()
    ..sort();
  return dup;
}

/// Este documento pode ser atribuído a este expositor?
///
/// Vale para tudo que é gravado por cliente — check-off, considerações,
/// especificações, classificação de mobiliário, prova de arte. Todos moram sob
/// o `firestoreId`, que é posicional; sem esta conferência, uma reordenação da
/// planilha entrega o documento de um stand para outro sem que nada apareça.
///
/// Documento SEM identidade gravada é aceito. Ele foi escrito antes deste
/// carimbo existir, e recusá-lo apagaria da tela todo check-off e toda
/// anotação que já estão lá — trocaria um erro raro por uma perda geral e
/// imediata. Ele volta a ser confiável na primeira vez que for regravado.
///
/// Documento COM identidade gravada que não bate é recusado. É o caso que
/// interessa: ali há dado de outro stand.
bool documentoDoCliente(
  Map<String, dynamic>? doc, {
  required String clientKey,
  required String nome,
}) {
  if (doc == null) return false;

  final doDoc = (doc['clientKey'] as String?) ?? '';
  if (doDoc.isNotEmpty && clientKey.isNotEmpty) return doDoc == clientKey;

  // Sem chave dos dois lados, o nome ainda serve de conferência — é o que a
  // ferramenta de aprovação já usa na contenção dela.
  final nomeDoc = (doc['clientName'] as String?) ?? '';
  if (nomeDoc.isNotEmpty) {
    return normalizeKeyPart(nomeDoc) == normalizeKeyPart(nome);
  }

  return true; // documento antigo, sem carimbo
}

/// O carimbo de identidade a gravar junto de qualquer documento por cliente.
Map<String, dynamic> carimboDoCliente({
  required String clientKey,
  required String nome,
}) =>
    {
      if (clientKey.isNotEmpty) 'clientKey': clientKey,
      if (nome.trim().isNotEmpty) 'clientName': nome.trim(),
    };
