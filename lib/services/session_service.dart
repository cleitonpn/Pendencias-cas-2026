import 'package:shared_preferences/shared_preferences.dart';
import '../utils/web_portal.dart';
import 'actor.dart';
import 'admin_api.dart';
import 'cloud_writes.dart';
import 'firestore_service.dart';

/// Persists the logged-in user session across app restarts using
/// SharedPreferences. The app has no Firebase Auth — sessions are keyed
/// by role + name (+ team for leaders).
class SessionService {
  static const _kRole = 'session_role';
  static const _kName = 'session_name';
  static const _kTeam = 'session_team';

  static Future<void> save({
    required String role,
    String name = '',
    String team = '',
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRole, role);
    await p.setString(_kName, name);
    await p.setString(_kTeam, team);
    // Na web o mesmo navegador pode ter também a sessão da organizadora.
    // Marcar aqui — ponto único por onde todo login passa — é o que faz o F5
    // numa URL sem fragmento voltar para o lugar certo.
    await p.setString(kLastWebPortal, kPortalApp);
    // Quem está logado passa a carimbar autoria nas alterações de pendência.
    Actor.name = name;
    Actor.role = role;
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kRole);
    await p.remove(_kName);
    await p.remove(_kTeam);
    // Sair do app tem de derrubar também a sessão de gestão; do contrário o
    // token continuaria valendo no aparelho para o próximo que entrasse.
    await AdminApi.clearToken();
    FirestoreService.clearUserCache();
    // Falha de gravação pendente é do usuário que saiu; deixá-la na tela do
    // próximo só confundiria.
    CloudWrites.clear();
    Actor.clear();
  }

  /// Returns `{'role', 'name', 'team'}` if a valid session exists, else null.
  static Future<Map<String, String>?> get() async {
    final p = await SharedPreferences.getInstance();
    final role = p.getString(_kRole);
    if (role == null || role.isEmpty) return null;
    return {
      'role': role,
      'name': p.getString(_kName) ?? '',
      'team': p.getString(_kTeam) ?? '',
    };
  }
}
