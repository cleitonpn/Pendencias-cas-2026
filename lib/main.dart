import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'providers/app_provider.dart';
import 'utils/desktop_db.dart';
import 'services/notification_service.dart';
import 'app_home.dart';

/// Background/terminated FCM handler. Must be a top-level function.
/// The system displays the notification automatically; nothing to do here.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // Initialize FFI SQLite on desktop (no-op on web and mobile).
  if (!kIsWeb) initDesktopDatabase();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Push notifications (Android/iOS only — no-op on desktop/web).
  if (isMobile) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await NotificationService.init();
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: const CasApp(),
    ),
  );
}

class CasApp extends StatelessWidget {
  const CasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Montagem USET',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: NotificationService.messengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A5F),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: buildHome(),
    );
  }
}
