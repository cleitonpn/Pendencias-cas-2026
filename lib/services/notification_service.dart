import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../utils/fcm_topics.dart';

/// Handles push notifications via Firebase Cloud Messaging.
///
/// FCM is only available on Android/iOS — on Windows/Linux/macOS/web all
/// methods are safe no-ops, so the desktop build keeps working normally.
class NotificationService {
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static bool get _supported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static bool _initialized = false;

  /// Requests permission and wires up foreground message handling.
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
  }

  /// Subscribes this device to the topics for a given role, after first
  /// clearing any previously-subscribed role topics.
  static Future<void> subscribeAdmin() => _subscribe(['admins']);

  static Future<void> subscribeProducer(String producerName) =>
      _subscribe([fcmTopic('producer', producerName)]);

  static Future<void> subscribeTeam(String team) =>
      _subscribe([fcmTopic('team', team)]);

  static Future<void> _subscribe(List<String> topics) async {
    if (!_supported) return;
    try {
      for (final t in topics) {
        await FirebaseMessaging.instance.subscribeToTopic(t);
      }
    } catch (_) {}
  }
}
