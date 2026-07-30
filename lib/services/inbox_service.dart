import 'package:shared_preferences/shared_preferences.dart';
import '../models/meeting.dart';
import '../models/pending_item.dart';
import 'actor.dart';
import 'firestore_service.dart';

/// Uma novidade para a pessoa logada.
class InboxItem {
  final String type; // 'pending' | 'aviso' | 'meeting'
  final String title;
  final String subtitle;
  final DateTime at;
  final String clientId;
  final String pendingId;
  final String fairName;

  const InboxItem({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.at,
    this.clientId = '',
    this.pendingId = '',
    this.fairName = '',
  });
}

/// Novidades de quem está logado.
///
/// Existe por causa do app web: consultores e líderes de iPhone acessam por
/// ele e não recebem notificação nenhuma — nem do navegador, nem do sistema.
/// Sem isso, a única forma de saber que chegou serviço era ficar abrindo as
/// telas para conferir.
///
/// No Android também serve: a notificação some da barra depois de tocada, e
/// aqui a lista continua.
class InboxService {
  InboxService._();

  static const _kSeen = 'inbox_last_seen';

  static Future<DateTime> lastSeen() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kSeen);
    // Primeira vez: começa agora, para a caixa não nascer com meses de
    // histórico marcado como novidade.
    return DateTime.tryParse(raw ?? '') ?? DateTime.now();
  }

  static Future<void> markSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSeen, DateTime.now().toIso8601String());
  }

  /// Verdadeiro quando este chamado diz respeito a quem está logado.
  ///
  /// Vale a mesma regra das notificações: admin, gerente e analista veem
  /// tudo; os demais só o que passa por eles.
  static bool _minha(PendingItem p) {
    final eu = Actor.name.toLowerCase().trim();
    if (eu.isEmpty) return false;
    switch (Actor.role) {
      case 'admin':
      case 'manager':
      case 'analyst':
        return true;
      case 'producer':
        return p.producerName.toLowerCase().trim() == eu;
      case 'consultant':
        return p.consultantName.toLowerCase().trim() == eu;
      case 'leader':
        return p.responsible.toLowerCase().trim() == eu;
      default:
        return false;
    }
  }

  static bool _meuAviso(Map<String, dynamic> a) {
    final tipo = (a['targetType'] as String?) ?? 'groups';
    if (tipo == 'groups') {
      final grupos = ((a['targetGroups'] as List?) ?? const [])
          .map((g) => g.toString())
          .toList();
      if (grupos.isEmpty || grupos.contains('todos')) return true;
      const porPapel = {
        'producer': 'produtores',
        'consultant': 'consultores',
        'leader': 'lideres',
        'analyst': 'analistas',
        'admin': 'admins',
        'manager': 'admins',
        'logistica': 'logistica',
      };
      return grupos.contains(porPapel[Actor.role]);
    }
    final eu = Actor.name.toLowerCase().trim();
    return ((a['targetUsers'] as List?) ?? const []).any((u) {
      final m = Map<String, dynamic>.from(u as Map);
      return ((m['name'] as String?) ?? '').toLowerCase().trim() == eu &&
          (m['role'] as String?) == Actor.role;
    });
  }

  /// Novidades desde [desde], da mais recente para a mais antiga.
  ///
  /// Cada fonte é lida em try/catch próprio: uma falhar não pode esvaziar a
  /// caixa inteira e fazer parecer que não há nada.
  static Future<List<InboxItem>> load({
    required DateTime desde,
    required List<String> fairNames,
  }) async {
    final itens = <InboxItem>[];

    for (final fair in fairNames) {
      try {
        final pendencias =
            await FirestoreService.streamPendingByFair(fair).first;
        for (final p in pendencias) {
          if (!p.createdAt.isAfter(desde)) continue;
          if (p.isResolved || p.isRejected) continue;
          if (!_minha(p)) continue;
          itens.add(InboxItem(
            type: 'pending',
            title: p.team.isEmpty
                ? 'Nova pendência'
                : 'Nova pendência — ${p.team}',
            subtitle: '${p.clientName}'
                '${p.local.isEmpty ? '' : ' (Stand ${p.local})'}'
                ': ${p.description}',
            at: p.createdAt,
            clientId: p.clientId,
            pendingId: p.firestoreId ?? '',
            fairName: fair,
          ));
        }
      } catch (_) {
        // Feira indisponível agora; as outras continuam.
      }
    }

    try {
      final avisos = await FirestoreService.streamAvisos().first;
      for (final a in avisos) {
        final at = DateTime.tryParse((a['createdAt'] as String?) ?? '');
        if (at == null || !at.isAfter(desde)) continue;
        if (!_meuAviso(a)) continue;
        itens.add(InboxItem(
          type: 'aviso',
          title: '⚠️ ${(a['title'] as String?) ?? 'Aviso'}',
          subtitle: (a['body'] as String?) ?? '',
          at: at,
        ));
      }
    } catch (_) {}

    try {
      final reunioes = await FirestoreService.streamMeetings().first;
      for (final m in reunioes) {
        if (m.canceled || m.isPast) continue;
        if (!m.createdAt.isAfter(desde)) continue;
        if (!m.includes(Actor.name, Actor.role)) continue;
        itens.add(InboxItem(
          type: 'meeting',
          title: '📅 Reunião — ${m.title}',
          subtitle: '${m.fairName}'
              '${m.location.isEmpty ? '' : ' · ${m.location}'}',
          at: m.createdAt,
          fairName: m.fairName,
        ));
      }
    } catch (_) {}

    itens.sort((a, b) => b.at.compareTo(a.at));
    return itens;
  }
}
