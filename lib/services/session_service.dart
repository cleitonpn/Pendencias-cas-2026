import 'package:shared_preferences/shared_preferences.dart';

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
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kRole);
    await p.remove(_kName);
    await p.remove(_kTeam);
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
