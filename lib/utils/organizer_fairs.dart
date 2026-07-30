/// Lê o vínculo entre organizadora e feiras.
///
/// Existem dois formatos gravados: `fairIds` (lista, formato atual) e
/// `fairId` (um número só, de antes de uma organizadora poder tocar mais de
/// uma feira ao mesmo tempo). Os cadastros antigos continuam no banco, então
/// a leitura precisa entender os dois — e os dois aparecem ora como número,
/// ora como texto, dependendo de por onde passaram.
List<int> organizerFairIdsFrom(Object? fairIds, Object? fairId) {
  final out = <int>[];

  void add(Object? v) {
    final id = v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
    if (id != null && !out.contains(id)) out.add(id);
  }

  if (fairIds is List) {
    for (final v in fairIds) {
      add(v);
    }
  }
  // O campo antigo só entra se não houver lista: quando os dois existem, a
  // lista é a verdade — ela é gravada junto e já contém o valor antigo.
  if (out.isEmpty) add(fairId);

  return out;
}
