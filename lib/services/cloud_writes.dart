import 'package:flutter/foundation.dart';

/// Uma gravação na nuvem que falhou e pode ser repetida.
class FailedWrite {
  final String what;
  final Future<void> Function() op;
  final Object error;
  final DateTime at;

  const FailedWrite({
    required this.what,
    required this.op,
    required this.error,
    required this.at,
  });
}

/// Gravações na nuvem que não podem travar a tela, mas também não podem
/// sumir.
///
/// O padrão em todo o app era `.catchError((_) {})`: a gravação saía sem
/// esperar resposta — o que é certo, porque no pavilhão a rede cai e o
/// Firestore reenvia sozinho ao reconectar — mas o erro era jogado fora. O
/// problema é que nem todo erro é de rede. Permissão negada, documento
/// inexistente e dado inválido falham para sempre, e falhavam calados: a
/// tela mostrava sucesso e a alteração nunca chegava a lugar nenhum. Foi
/// assim que se perderam os check-offs e foi assim que uma feira excluída
/// voltava do além.
///
/// Aqui a gravação continua sem bloquear, mas a falha fica registrada, some
/// da lista quando dá certo, e a tela consegue mostrar "N alterações não
/// subiram" com um botão de tentar de novo.
class CloudWrites {
  CloudWrites._();

  static final List<FailedWrite> _failed = [];

  /// Quantas gravações estão pendentes de retentativa. As telas escutam para
  /// mostrar o aviso.
  static final ValueNotifier<int> failureCount = ValueNotifier(0);

  static List<FailedWrite> get failures => List.unmodifiable(_failed);

  /// Dispara [op] sem esperar. Se falhar, guarda para retentativa.
  ///
  /// [what] é o texto mostrado ao usuário, em português e no que ele
  /// reconhece: "conclusão da pendência", não "updatePendingContent".
  static void fireAndForget(String what, Future<void> Function() op) {
    op().catchError((Object e) {
      _record(what, op, e);
    });
  }

  /// Versão que espera o resultado e devolve o erro em vez de lançar.
  ///
  /// Para quando a tela precisa dizer na hora se deu certo — apagar algo, por
  /// exemplo, onde seguir como se tivesse funcionado é pior do que esperar.
  static Future<Object?> run(String what, Future<void> Function() op) async {
    try {
      await op();
      return null;
    } catch (e) {
      _record(what, op, e);
      return e;
    }
  }

  static void _record(String what, Future<void> Function() op, Object e) {
    // Uma falha por operação: se o produtor editar o mesmo chamado três
    // vezes offline, a lista não precisa mostrar três avisos iguais.
    _failed.removeWhere((f) => f.what == what);
    _failed.add(FailedWrite(
      what: what,
      op: op,
      error: e,
      at: DateTime.now(),
    ));
    failureCount.value = _failed.length;
    if (kDebugMode) {
      debugPrint('[CloudWrites] falhou: $what → $e');
    }
  }

  /// Tenta de novo tudo o que falhou. Devolve quantas continuam falhando.
  static Future<int> retryAll() async {
    final pendentes = List<FailedWrite>.of(_failed);
    _failed.clear();
    failureCount.value = 0;

    for (final f in pendentes) {
      try {
        await f.op();
      } catch (e) {
        _record(f.what, f.op, e);
      }
    }
    return _failed.length;
  }

  /// Descarta as falhas sem tentar de novo. Usado ao sair da sessão, para a
  /// pendência de um usuário não aparecer para o próximo.
  static void clear() {
    _failed.clear();
    failureCount.value = 0;
  }
}
