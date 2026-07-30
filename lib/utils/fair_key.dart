/// Chave estável para o nome de uma feira.
///
/// Usada para saber se uma feira da planilha mestra está na lista de
/// ignoradas. O nome digitado na coluna FEIRA varia entre sincronizações —
/// maiúsculas, espaço a mais, acento — e comparar o texto cru faria a feira
/// excluída voltar na primeira vez que alguém redigitasse o nome de outro
/// jeito.
///
/// O resultado também serve como id de documento no Firestore, por isso só
/// sobram letras, números e sublinhado.
String fairKey(String name) {
  var s = name.toLowerCase().trim();
  const accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'ê': 'e', 'è': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };
  accents.forEach((k, v) => s = s.split(k).join(v));
  return s.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
}
