import 'pin_service.dart';

/// Uma pessoa cadastrada no app.
class AppUser {
  final String name;
  final String role;
  final String team;

  const AppUser({required this.name, required this.role, this.team = ''});

  /// Identidade estável para seleção em tela.
  String get key => '${role}_$name';

  String get roleLabel => switch (role) {
        'producer' => 'Produtor',
        'consultant' => 'Consultor',
        'leader' => 'Líder',
        'analyst' => 'Analista',
        'manager' => 'Gerente',
        'admin' => 'Admin',
        'logistica' => 'Logística',
        _ => role,
      };

  Map<String, dynamic> toMap() => {'name': name, 'role': role, 'team': team};
}

/// Lista de quem existe no app.
///
/// Antes as telas montavam essa lista a partir da coleção `presence`, que só
/// registra quem abriu o app recentemente. O efeito era um aviso dirigido não
/// encontrar a pessoa justamente quando ela estava com o celular guardado —
/// que é quando o aviso mais importa. Aqui a lista vem do cadastro.
class DirectoryService {
  /// Papéis que podem receber aviso ou convite de reunião. Organizadora fica
  /// de fora: ela usa o portal web, sem notificação.
  static const roles = [
    'producer',
    'consultant',
    'leader',
    'analyst',
    'manager',
    'admin',
    'logistica',
  ];

  /// Papéis que entram sempre no aviso de uma feira, trabalhem nela ou não.
  static const alwaysIncluded = ['analyst', 'manager', 'admin'];

  static List<AppUser>? _cache;

  /// Todos os cadastrados. [failed] indica que alguma consulta não respondeu —
  /// a lista sai incompleta e a tela precisa dizer isso, em vez de deixar
  /// alguém de fora do aviso em silêncio.
  static Future<({List<AppUser> users, bool failed})> all(
      {bool refresh = false}) async {
    if (!refresh && _cache != null) {
      return (users: _cache!, failed: false);
    }
    final out = <AppUser>[];
    var failed = false;

    for (final role in roles) {
      final r = await PinService.listUsers(role);
      if (r.failed) {
        failed = true;
        continue;
      }
      for (final u in r.users) {
        final name = (u['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        out.add(AppUser(
          name: name,
          role: role,
          team: (u['team'] as String?) ?? '',
        ));
      }
    }

    out.sort((a, b) {
      final r = roles.indexOf(a.role).compareTo(roles.indexOf(b.role));
      return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    if (!failed) _cache = out;
    return (users: out, failed: failed);
  }

  /// Casa nomes vindos da planilha com os cadastros do app.
  ///
  /// A planilha traz o nome digitado à mão; o cadastro traz o nome escolhido
  /// no login. Comparar o texto cru deixaria de fora quem foi digitado com
  /// caixa ou espaçamento diferente — e ficar de fora de um aviso é uma falha
  /// silenciosa.
  static List<AppUser> match(
      List<AppUser> everyone, String role, Iterable<String> names) {
    final wanted = names
        .map((n) => n.toLowerCase().trim())
        .where((n) => n.isNotEmpty)
        .toSet();
    return everyone
        .where((u) =>
            u.role == role && wanted.contains(u.name.toLowerCase().trim()))
        .toList();
  }
}
