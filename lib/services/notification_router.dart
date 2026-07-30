import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/client.dart';
import '../models/fair.dart';
import '../providers/app_provider.dart';
import 'database_service.dart';
import 'session_service.dart';
import '../screens/client_detail_screen.dart';
import '../screens/producer_client_detail_screen.dart';
import '../screens/consultant_client_detail_screen.dart';
import '../screens/analyst_client_detail_screen.dart';
import '../screens/meeting_list_screen.dart';

/// Abre a tela correspondente quando o usuário toca numa notificação.
///
/// Antes as notificações não levavam a lugar nenhum: as Cloud Functions
/// enviavam apenas `title`/`body`, sem `data`, e o app não escutava nenhum dos
/// eventos de toque. Agora o payload traz `clientId`, e este roteador resolve
/// o cliente (em qualquer feira), seleciona a feira dele e abre o detalhe do
/// stand na tela correta para o papel de quem está logado.
class NotificationRouter {
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Guarda um toque recebido antes do app estar pronto (abertura a partir do
  /// estado encerrado), para ser processado assim que houver navigator.
  static Map<String, dynamic>? _pending;

  static void handle(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    final nav = navigatorKey?.currentState;
    if (nav == null) {
      _pending = data; // app ainda subindo — processa depois
      return;
    }
    _open(data);
  }

  /// Processa um toque que chegou antes do app estar pronto. Chamado após a
  /// splash decidir a tela inicial.
  static void flushPending() {
    final data = _pending;
    if (data == null) return;
    _pending = null;
    _open(data);
  }

  static Future<void> _open(Map<String, dynamic> data) async {
    final nav = navigatorKey?.currentState;
    final context = navigatorKey?.currentContext;
    if (nav == null || context == null) return;

    // Convite ou lembrete de reunião: não há stand para abrir, a tela certa é
    // a agenda.
    if ((data['type'] ?? '').toString() == 'meeting') {
      nav.push(MaterialPageRoute(builder: (_) => const MeetingListScreen()));
      return;
    }

    final clientId = (data['clientId'] ?? '').toString();
    if (clientId.isEmpty) return;

    final client = await DatabaseService.findClientByAnyId(clientId);
    if (client == null) return; // planilha ainda não sincronizada neste aparelho

    if (!context.mounted) return;
    final provider = context.read<AppProvider>();

    // A notificação pode ser de uma feira diferente da que está aberta.
    if (provider.currentFair?.id != client.fairId) {
      Fair? target;
      for (final f in provider.fairs) {
        if (f.id == client.fairId) target = f;
      }
      if (target != null) await provider.selectFair(target);
    }

    final session = await SessionService.get();
    final role = session?['role'] ?? 'admin';
    final name = session?['name'] ?? '';

    final screen = _screenFor(role, name, client);
    if (screen == null) return;

    navigatorKey?.currentState
        ?.push(MaterialPageRoute(builder: (_) => screen));
  }

  static Widget? _screenFor(String role, String name, Client client) {
    switch (role) {
      case 'producer':
        return ProducerClientDetailScreen(
            client: client, producerName: name);
      case 'consultant':
        return ConsultantClientDetailScreen(
            client: client, consultantName: name);
      case 'analyst':
        return AnalystClientDetailScreen(
            client: client, analystName: name);
      case 'admin':
      case 'manager':
      case 'leader':
        return ClientDetailScreen(client: client);
      default:
        return null;
    }
  }
}
