import '../models/client.dart';

/// Assinatura do conteúdo de um expositor, usada para saber o que mudou.
///
/// Sem ela, cada sincronização reescreveria toda a planilha no Firestore —
/// centenas de gravações por aparelho, várias vezes ao dia, para dados quase
/// sempre idênticos. Com ela, só sobe o que realmente mudou na planilha.
///
/// Campos de controle ficam de fora de propósito:
///
///  - `fair_id` e `row_id` dependem do id local da feira, que varia entre
///    aparelhos. Entrariam como diferença falsa e fariam todo aparelho
///    reescrever tudo do outro, num pinga-pinga sem fim.
///  - `is_completed` e `completed_at` são o check-off, que não vem da
///    planilha e mora em `client_status`. Incluí-los faria marcar um stand
///    como concluído parecer alteração da planilha.
String clientFingerprint(Client c) {
  const ignorados = {
    'fair_id',
    'row_id',
    'is_completed',
    'completed_at',
  };
  final mapa = c.toMap();
  final chaves = mapa.keys.where((k) => !ignorados.contains(k)).toList()
    ..sort();
  // Separador que não aparece em texto de planilha, para dois campos vizinhos
  // não se confundirem ("ab"+"c" contra "a"+"bc").
  return chaves.map((k) => '$k=${mapa[k] ?? ''}').join('');
}
