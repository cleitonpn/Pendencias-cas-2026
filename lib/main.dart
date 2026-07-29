import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tzlib;
import 'firebase_options.dart';
import 'providers/app_provider.dart';
import 'utils/desktop_db.dart';
import 'services/notification_service.dart';
import 'services/notification_router.dart';
import 'services/update_service.dart';
import 'widgets/update_dialog.dart';
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

  // Initialize timezone data for local notification scheduling (native only).
  if (!kIsWeb) {
    tz.initializeTimeZones();
    tzlib.setLocalLocation(tzlib.getLocation('America/Sao_Paulo'));
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Sign in anonymously so every client has a Firebase identity.
  // This is invisible to the user — no login screen, no UI change.
  // Required for Firestore rules that check request.auth != null.
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (_) {
    // Anonymous auth not yet enabled in Firebase Console or unavailable.
    // App continues to work — rules enforcement will be added in a second step.
  }

  // Push notifications (Android/iOS only — no-op on desktop/web).
  if (isMobile) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await NotificationService.init();
  }

  // O router precisa do navigator para abrir a tela do toque. init() roda
  // antes do runApp, então um toque vindo do app encerrado fica guardado até
  // a splash chamar flushPending().
  NotificationRouter.navigatorKey = CasApp.navigatorKey;

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: const CasApp(),
    ),
  );
}

class CasApp extends StatefulWidget {
  const CasApp({super.key});

  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  State<CasApp> createState() => _CasAppState();
}

class _CasAppState extends State<CasApp> {
  @override
  void initState() {
    super.initState();
    // After the first screen is up, check for an app update (Android only;
    // no-op on web/desktop) and offer to download + install it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    await Future.delayed(const Duration(seconds: 2));
    final info = await UpdateService.checkForUpdate();
    if (info == null) return;
    final ctx = CasApp.navigatorKey.currentContext;
    if (ctx == null) return;
    await showUpdateFlow(ctx, info);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Montagem USET',
      debugShowCheckedModeBanner: false,
      navigatorKey: CasApp.navigatorKey,
      scaffoldMessengerKey: NotificationService.messengerKey,
      // Sem isto os seletores de data nativos aparecem em inglês.
      locale: const Locale('pt', 'BR'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
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
