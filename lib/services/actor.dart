import 'session_service.dart';

/// Quem está mexendo no app agora.
///
/// Serve para carimbar autoria em toda alteração de pendência. Antes só a
/// conclusão registrava quem fez; edição, aprovação e recusa não registravam
/// nada. Quando a organizadora diz "abri esse chamado às 9h e ninguém fez
/// nada", não havia como reconstruir o que aconteceu.
///
/// Fica em memória de propósito: ler a sessão do disco a cada gravação
/// atrasaria o caminho crítico em campo, e o valor não muda durante a sessão.
class Actor {
  Actor._();

  static String name = '';
  static String role = '';

  /// Carrega da sessão salva. Chamado no arranque e depois de cada login.
  static Future<void> load() async {
    final s = await SessionService.get();
    name = s?['name'] ?? '';
    role = s?['role'] ?? '';
  }

  static void clear() {
    name = '';
    role = '';
  }

  static String get roleLabel => switch (role) {
        'producer' => 'Produtor',
        'consultant' => 'Consultor',
        'leader' => 'Líder',
        'analyst' => 'Analista',
        'manager' => 'Gerente',
        'admin' => 'Admin',
        'logistica' => 'Logística',
        'mobiliario' => 'Mobiliário',
        'organizadora' => 'Organizadora',
        _ => '',
      };

  /// Carimbo anexado a toda alteração de pendência.
  static Map<String, dynamic> get stamp => {
        'lastActionBy': name,
        'lastActionRole': role,
        'lastActionAt': DateTime.now().toIso8601String(),
      };
}
