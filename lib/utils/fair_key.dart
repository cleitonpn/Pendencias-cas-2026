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

/// Id numérico ESTÁVEL de uma feira derivada de planilha mestra.
///
/// Este é o coração de um defeito que duplicava feiras no app. As derivadas
/// nasciam com o id que o SQLite daquele aparelho tinha a dar em seguida — um
/// número local — e esse id virava o id do documento no Firestore. Dois
/// aparelhos sincronizando a mesma planilha mestra criavam a MESMA feira com
/// ids diferentes, publicavam dois documentos, e todo mundo passava a ver a
/// feira duas vezes. Cada cópia com o seu próprio modo, porque o modo mora no
/// documento: era por isso que a mesma feira aparecia uma em Pré-produção e
/// outra em Manutenção.
///
/// Derivado do nome, o id é o mesmo em qualquer aparelho, e a segunda gravação
/// cai em cima da primeira em vez de criar uma feira nova.
///
/// A faixa começa alto de propósito, para não colidir com os ids pequenos que
/// o autoincremento já distribuiu às feiras criadas à mão.
int derivedFairId(String name) {
  final key = fairKey(name);
  if (key.isEmpty) return 0;
  // FNV-1a de 32 bits. Escrito à mão porque `String.hashCode` do Dart não é
  // estável entre execuções nem entre plataformas — e "estável" é a única
  // coisa que esta função precisa ser.
  var h = 0x811c9dc5;
  for (final c in key.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return 1000000 + (h % 1000000000);
}

/// Ordem de "avanço" do modo da feira, para a fusão de duplicatas saber qual
/// preservar.
///
/// Manutenção é o mais avançado: é o modo que abre o QR para o expositor.
/// Perder isso numa fusão fecharia o atendimento no meio do evento sem
/// ninguém entender por quê.
int fairModeRank(String mode) => switch (mode) {
      'manutencao' => 3,
      'producao' => 2,
      'pre_producao' => 1,
      _ => 0,
    };
