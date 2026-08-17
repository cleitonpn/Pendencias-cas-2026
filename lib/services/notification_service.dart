import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_router.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/fair.dart';
import '../utils/fcm_topics.dart';

/// Handles push notifications (FCM) and local scheduled notifications.
///
/// Only active on Android/iOS — all methods are safe no-ops on web/desktop.
class NotificationService {
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static bool get _supported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static bool _initialized = false;
  static final _localPlugin = FlutterLocalNotificationsPlugin();
  static const _montageReminderId = 1001;
  static const _fcmChannelId = 'fcm_foreground';
  static const _fcmChannel = AndroidNotificationDetails(
    'fcm_foreground',
    'Notificações em tempo real',
    channelDescription: 'Alertas recebidos enquanto o app está aberto',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
  );

  /// Requests FCM permission and wires up foreground message handling.
  /// Call once after Firebase.initializeApp().
  static Future<void> init() async {
    if (!_supported || _initialized) return;
    _initialized = true;
    try {
      await FirebaseMessaging.instance.requestPermission();
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
              alert: true, badge: true, sound: true);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final n = message.notification;
        if (n == null) return;

        // Show in the system notification bar (works even when app is open)
        _localPlugin.show(
          message.hashCode,
          n.title,
          n.body,
          const NotificationDetails(android: _fcmChannel),
          // Sem payload o toque não teria como saber o que abrir.
          payload: jsonEncode(message.data),
        );

        // Also show an in-app snackbar for immediate attention
        final messenger = messengerKey.currentState;
        if (messenger == null) return;
        messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 5),
          backgroundColor: const Color(0xFF1E3A5F),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(n.title ?? 'Notificação',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white)),
              if (n.body != null)
                Text(n.body!,
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ));
      });
    } catch (_) {
      // Messaging not available — ignore.
    }

    // Initialize local notifications plugin.
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            NotificationRouter.handle(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {}
      },
    );

    try {
      // App em segundo plano: usuário tocou na notificação do sistema.
      FirebaseMessaging.onMessageOpenedApp.listen(
          (message) => NotificationRouter.handle(message.data));

      // App estava encerrado: a mensagem que o abriu fica guardada até a
      // splash terminar (ver NotificationRouter.flushPending).
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) NotificationRouter.handle(initial.data);
    } catch (_) {
      // Messaging indisponível — ignora.
    }
  }

  // ── Local daily reminder ───────────────────────────────────────────────────

  /// Schedule the daily 18h montage reminder if any fair is in 'producao'
  /// mode, or cancel it if none are. Call this every time the producer's fair
  /// list is loaded or changes.
  static Future<void> syncMontageReminder(List<Fair> fairs) async {
    if (!_supported) return;
    final inProducao = fairs.any((f) => f.isProduction);
    if (inProducao) {
      await _scheduleDailyAt18h();
    } else {
      await _localPlugin.cancel(_montageReminderId);
    }
  }

  static Future<void> _scheduleDailyAt18h() async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'montagem_lembrete',
        'Lembrete de Montagem',
        channelDescription:
            'Lembrete diário para registrar o progresso da montagem às 18h',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, 18);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    try {
      await _localPlugin.zonedSchedule(
        _montageReminderId,
        'Hora de atualizar a montagem!',
        'Registre o progresso do dia com uma foto de cada stand.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // Scheduling not supported on this device — ignore.
    }
  }

  // ── FCM topic subscriptions ────────────────────────────────────────────────

  static Future<void> subscribeAdmin() =>
      _subscribe(['admins', 'new_clients', 'group_admins']);

  /// O gerente entrava só pelo tópico coletivo 'admins', então um aviso
  /// dirigido a um gerente específico caía em todos os administradores. O
  /// tópico por nome é o que permite falar com um só.
  static Future<void> subscribeManager(String name) =>
      _subscribe([
        fcmTopic('manager', name),
        'admins',
        'new_clients',
        'group_admins',
      ]);

  static Future<void> subscribeProducer(String producerName) =>
      _subscribe([fcmTopic('producer', producerName), 'new_clients', 'group_produtores']);

  static Future<void> subscribeConsultant(String consultantName) =>
      _subscribe([fcmTopic('consultant', consultantName), 'new_clients', 'group_consultores']);

  /// O líder passa a receber por NOME, não pela equipe inteira: antes todo
  /// líder de "Limpeza" recebia qualquer pendência de Limpeza, mesmo de
  /// clientes que não são dele. O tópico da equipe continua assinado apenas
  /// como rede de segurança para pendências sem responsável definido.
  static Future<void> subscribeLeader(String leaderName, String team) =>
      _subscribe([
        fcmTopic('leader', leaderName),
        fcmTopic('team', team),
        'new_clients',
        'group_lideres',
      ]);

  static Future<void> subscribeAnalyst(String analystName) =>
      _subscribe([fcmTopic('analyst', analystName), 'new_clients', 'group_analistas']);

  static Future<void> subscribeLogistics(String name) =>
      _subscribe([fcmTopic('logistica', name), 'group_logistica']);

  static Future<void> subscribeMobiliario(String name) =>
      _subscribe([fcmTopic('mobiliario', name), 'group_mobiliario']);

  static Future<void> _subscribe(List<String> topics) async {
    if (!_supported) return;
    try {
      for (final t in topics) {
        await FirebaseMessaging.instance.subscribeToTopic(t);
      }
    } catch (_) {}
  }
}
