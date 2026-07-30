import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tzlib;
import 'firebase_options.dart';
import 'providers/app_provider.dart';
import 'utils/desktop_db.dart';
import 'services/auth_bootstrap.dart';
import 'services/notification_service.dart';
import 'services/notification_router.dart';
import 'services/update_service.dart';
import 'widgets/update_dialog.dart';
import 'widgets/cloud_write_banner.dart';
import 'widgets/blocked_version_screen.dart';
import 'services/version_gate.dart';
import 'app_home.dart';

/// Background/terminated FCM handler. Must be a top-level function.
/// The system displays the notification automatically; nothing to do here.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Nomes de dia e mês em português para o DateFormat. Sem isto, qualquer
  // formatação com locale explícito estoura em tempo de execução — e a
  // agenda de reuniões usa uma.
  await initializeDateFormatting('pt_BR');
  Intl.defaultLocale = 'pt_BR';

  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // Driver do SQLite por plataforma (import condicional em utils/desktop_db):
  // FFI no desktop, WebAssembly + IndexedDB no navegador, nativo no celular.
  // Precisa rodar na web também — é o que mantém as telas do app funcionando
  // lá sem nenhuma alteração.
  initDesktopDatabase();

  // Initialize timezone data for local notification scheduling (native only).
  if (!kIsWeb) {
    tz.initializeTimeZones();
    tzlib.setLocalLocation(tzlib.getLocation('America/Sao_Paulo'));
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Identidade anônima no Firebase: sem ela as regras do Firestore negam toda
  // leitura. O erro deixa de ser engolido — fica registrado em
  // AuthBootstrap.lastError para as telas poderem dizer o que houve, em vez
  // de mostrarem "nenhum usuário cadastrado".
  await AuthBootstrap.ensureSignedIn();

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
  /// Preenchido quando a versão instalada está abaixo da mínima exigida.
  /// Enquanto isso o app não abre — ver BlockedVersionScreen.
  VersionVerdict? _blocked;

  @override
  void initState() {
    super.initState();
    // After the first screen is up, check for an app update (Android only;
    // no-op on web/desktop) and offer to download + install it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    _checkVersionGate();
  }

  Future<void> _checkVersionGate() async {
    final v = await VersionGate.check();
    if (v.blocked && mounted) setState(() => _blocked = v);
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
      // A faixa de "não salvo na nuvem" fica AQUI, envolvendo o app inteiro,
      // em vez de repetida em cada tela: a gravação que falha pode ter partido
      // de qualquer uma delas, e o usuário precisa ver o aviso onde estiver.
      builder: (context, child) =>
          CloudWriteScope(child: child ?? const SizedBox.shrink()),
      home: _blocked != null
          ? BlockedVersionScreen(verdict: _blocked!)
          : buildHome(),
    );
  }
}
