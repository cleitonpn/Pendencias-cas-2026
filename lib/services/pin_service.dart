import 'package:cloud_functions/cloud_functions.dart';

/// Resultado da verificação de PIN feita no servidor.
class PinResult {
  final bool ok;

  /// 'nao_cadastrado' | 'pin_incorreto' | 'erro' — null quando ok.
  final String? reason;

  /// Campos auxiliares do papel: a equipe do líder, a feira da organizadora.
  final Map<String, dynamic> extra;

  const PinResult({required this.ok, this.reason, this.extra = const {}});

  String? get team => extra['team'] as String?;
  int? get fairId {
    final v = extra['fairId'];
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }
}

/// Acesso aos PINs pelo servidor.
///
/// Antes o app baixava a coleção inteira de PINs para montar a lista de nomes
/// e conferir o código digitado — e a regra do Firestore libera leitura a
/// qualquer sessão autenticada, inclusive a anônima dos portais públicos. Aqui
/// o PIN cadastrado nunca sai do servidor.
///
/// Enquanto as regras não são fechadas, o caminho antigo continua existindo
/// como reserva: se a função falhar (rede, função ainda propagando), quem
/// chama pode cair no acesso direto. Depois de fechar as regras essa reserva
/// deixa de funcionar sozinha — e é justamente esse o objetivo.
class PinService {
  static final _fn = FirebaseFunctions.instance;

  /// Nomes cadastrados para um papel. Lista vazia com [failed] verdadeiro
  /// significa "não consegui perguntar", não "não há ninguém".
  static Future<({List<Map<String, dynamic>> users, bool failed})> listUsers(
      String role) async {
    try {
      final res = await _fn.httpsCallable('listUsers').call({'role': role});
      final raw = (res.data as Map)['users'] as List? ?? const [];
      return (
        users: raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        failed: false,
      );
    } catch (_) {
      return (users: <Map<String, dynamic>>[], failed: true);
    }
  }

  /// Só os nomes, para as telas que não precisam dos campos auxiliares.
  static Future<({List<String> names, bool failed})> listNames(
      String role) async {
    final r = await listUsers(role);
    return (
      names: r.users
          .map((u) => (u['name'] as String?) ?? '')
          .where((n) => n.isNotEmpty)
          .toList(),
      failed: r.failed,
    );
  }

  static Future<PinResult> verify({
    required String role,
    required String name,
    required String pin,
  }) async {
    try {
      final res = await _fn.httpsCallable('verifyPin').call({
        'role': role,
        'name': name,
        'pin': pin,
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      return PinResult(
        ok: data['ok'] == true,
        reason: data['reason'] as String?,
        extra: data,
      );
    } catch (_) {
      // Falha de rede/função não pode ser lida como "PIN errado": seria
      // acusar o usuário de digitar errado por um problema nosso.
      return const PinResult(ok: false, reason: 'erro');
    }
  }
}
