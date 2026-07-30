import 'package:firebase_auth/firebase_auth.dart';

/// Login anônimo no Firebase, com o resultado guardado.
///
/// As regras do Firestore exigem `request.auth != null`. Sem essa sessão,
/// TODA leitura é negada — e como cada tela engolia o erro, a falha aparecia
/// como "nenhum usuário cadastrado", mandando o usuário falar com o
/// administrador por um problema de conexão/armazenamento.
///
/// No Safari do iPhone isso é bem mais provável do que no desktop: o
/// navegador restringe armazenamento, e o Firebase Auth precisa dele para
/// manter a sessão.
class AuthBootstrap {
  AuthBootstrap._();

  /// Mensagem do último erro, ou null se a sessão está de pé.
  static String? lastError;

  static bool get signedIn =>
      FirebaseAuth.instance.currentUser != null;

  /// Tenta entrar, com algumas repetições — no iOS a primeira tentativa pode
  /// falhar enquanto o navegador ainda libera o armazenamento.
  static Future<void> ensureSignedIn({int attempts = 3}) async {
    for (var i = 0; i < attempts; i++) {
      try {
        if (FirebaseAuth.instance.currentUser != null) {
          lastError = null;
          return;
        }
        await FirebaseAuth.instance.signInAnonymously();
        lastError = null;
        return;
      } catch (e) {
        lastError = e.toString();
        if (i < attempts - 1) {
          await Future.delayed(Duration(milliseconds: 400 * (i + 1)));
        }
      }
    }
  }
}
