import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gestão de usuários e PINs pelo servidor.
///
/// A tela de Configurações continua a mesma; o que muda é o caminho por
/// baixo. Antes ela lia e escrevia direto nas coleções `*_pins`, o que
/// obrigava as regras do Firestore a deixar qualquer sessão autenticada
/// mexer nelas — inclusive a sessão anônima dos portais públicos. Agora tudo
/// passa por `manageUsers`, que só aceita quem tem sessão de administrador.
class AdminApi {
  static const _kToken = 'admin_session_token';
  static const _kExpires = 'admin_session_expires';

  /// Precisa bater com ADMIN_SESSION_TTL_MS da function. Guardado também aqui
  /// para o app saber, sem rede, se a sessão ainda vale.
  static const _ttl = Duration(hours: 12);

  static final _fn = FirebaseFunctions.instance;

  static Future<String?> token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kToken);
  }

  /// Verdadeiro quando há sessão de gestão guardada e ainda dentro do prazo.
  static Future<bool> hasValidSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kToken) == null) return false;
    final exp = prefs.getInt(_kExpires) ?? 0;
    return DateTime.now().millisecondsSinceEpoch < exp;
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setInt(
        _kExpires, DateTime.now().add(_ttl).millisecondsSinceEpoch);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_kToken);
    await prefs.remove(_kToken);
    await prefs.remove(_kExpires);
    if (t != null) {
      try {
        await _fn.httpsCallable('adminLogout').call({'token': t});
      } catch (_) {
        // O token expira sozinho em 12h; falhar aqui não deixa nada aberto.
      }
    }
  }

  /// Confere o PIN de administrador no servidor e guarda a sessão.
  ///
  /// [reason] é 'pin_incorreto', 'nenhum_admin' ou 'erro' quando falha —
  /// falha de rede nunca vira "PIN errado".
  static Future<({bool ok, String? reason, String? name})> gate(
      String pin) async {
    try {
      final res = await _fn.httpsCallable('adminGate').call({'pin': pin});
      final data = Map<String, dynamic>.from(res.data as Map);
      if (data['ok'] == true) {
        await saveToken(data['token'] as String);
        return (ok: true, reason: null, name: data['name'] as String?);
      }
      return (ok: false, reason: data['reason'] as String?, name: null);
    } on FirebaseFunctionsException catch (e) {
      return (
        ok: false,
        reason: e.code == 'resource-exhausted' ? 'bloqueado' : 'erro',
        name: null,
      );
    } catch (_) {
      return (ok: false, reason: 'erro', name: null);
    }
  }

  /// Erro lançado quando a sessão de gestão caiu — a tela pede o PIN de novo.
  static bool isSessionError(Object e) {
    if (e is! FirebaseFunctionsException) return false;
    return e.code == 'unauthenticated' || e.code == 'permission-denied';
  }

  static Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final t = await token();
    final res = await _fn.httpsCallable('manageUsers').call({
      ...body,
      'token': t,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Usuários de um papel, com o PIN — só um admin autenticado chega aqui.
  static Future<List<Map<String, dynamic>>> list(String role) async {
    final data = await _call({'op': 'list', 'role': role});
    final raw = data['users'] as List? ?? const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> set(String role, String name,
      {String? pin, Map<String, dynamic>? extra}) async {
    await _call({
      'op': 'set',
      'role': role,
      'name': name,
      if (pin != null) 'pin': pin,
      if (extra != null) 'extra': extra,
    });
  }

  static Future<void> remove(String role, String name) async {
    await _call({'op': 'delete', 'role': role, 'name': name});
  }
}
