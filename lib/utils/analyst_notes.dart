/// Lê as considerações de um stand a partir do documento gravado.
///
/// Existem dois formatos no banco ao mesmo tempo:
///
///  - o novo, uma lista em `notes`, cada item com autor e data;
///  - o antigo, um texto solto em `text`/`link` no próprio documento, de
///    quando o stand só podia ter UMA consideração.
///
/// O antigo continua aparecendo como a primeira anotação. Migrar apagando
/// seria repetir exatamente a perda que a lista veio corrigir: a observação
/// de alguém sumindo sem ninguém saber que existiu.
///
/// Devolve da mais nova para a mais antiga.
List<Map<String, dynamic>> analystNotesFrom(Map<String, dynamic>? data) {
  if (data == null) return [];

  final lista = (data['notes'] as List?) ?? const [];
  final notas = lista
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  final legado = (data['text'] as String?) ?? '';
  final legadoLink = (data['link'] as String?) ?? '';
  // Entra SEMPRE que existir, não só quando a lista está vazia. Mostrar a
  // antiga apenas enquanto ninguém escreveu nada novo faria ela desaparecer
  // exatamente no momento em que a segunda pessoa anotasse — que é a perda
  // que esta lista veio impedir. Ela só sai quando alguém apaga de propósito.
  final jaTem = notas.any((n) => n['id'] == legadoId);
  if (!jaTem && (legado.isNotEmpty || legadoLink.isNotEmpty)) {
    notas.add({
      'id': legadoId,
      'text': legado,
      'link': legadoLink,
      'by': (data['updatedBy'] as String?) ?? '',
      'at': (data['updatedAt'] as String?) ?? '',
    });
  }

  // A data está em ISO-8601, que ordena certo como texto. Anotação sem data
  // (só o legado tem como ficar assim) vai para o fim, que é onde ela está no
  // tempo.
  notas.sort((a, b) =>
      ((b['at'] ?? '') as String).compareTo((a['at'] ?? '') as String));
  return notas;
}

/// Marca da consideração no formato antigo. Ela não está dentro do array, e
/// por isso apagar exige limpar os campos soltos do documento em vez de
/// remover um item da lista.
const legadoId = 'legado';
