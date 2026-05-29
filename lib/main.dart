import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:viora/Services/firebase_messaging_background.dart';
import 'package:viora/firebase_options.dart';
import 'package:viora/routes.dart';
import 'package:viora/size_config.dart';
import 'package:viora/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:provider/provider.dart';
import 'Screens/Splash/splashScreen.dart';
import 'Services/Global.dart';
import 'Services/UserProvider.dart';
import 'Services/AppConfigService.dart';
import 'Services/network_service.dart';
import 'constants.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  try {
    // Load environment variables
    await dotenv.load();
  } catch (e) {
    debugPrint('Error loading environment variables: $e');
  }

  // Must be registered before runApp (separate isolate for background delivery).
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  debugPrint("⚡ APP START");
  final appStartTime = DateTime.now();

  // Show system UI overlays (status bar and navigation bar)
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );

  // Set status bar and navigation bar colors
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.light,
    ),
  );

  // Disable landscape mode - lock app to portrait only
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    //   DeviceOrientation.portraitDown,
  ]);

  final appCheckReady = await _initializeStrictAppCheck();
  if (!appCheckReady) {
    FlutterNativeSplash.remove();
    runApp(const _AppCheckBlockedApp());
    return;
  }

  final globals = await Globals.init();

  // Initialize Network Service for connectivity monitoring
  debugPrint('🌐 Initializing Network Service...');
  await NetworkService().initialize();
  debugPrint('✅ Network Service initialized');

  // Load AppConfig before UI so config-driven screens have data immediately.
  try {
    await AppConfigService.loadConfig();
    debugPrint('✅ AppConfig loaded before runApp');
  } catch (e) {
    // Keep startup resilient if config fetch is slow or fails.
    debugPrint('⚠️ AppConfig pre-load failed/timed out: $e');
  }

  final elapsed = DateTime.now().difference(appStartTime).inMilliseconds;
  debugPrint("⚡ main() completed in ${elapsed}ms - starting UI");

  runApp(
    MultiProvider(
      providers: [
        Provider<Globals>.value(value: globals),
        ChangeNotifierProvider<UserProvider>.value(value: globals.userProvider),
      ],
      child: MyApp(),
    ),
  );
}

Future<bool> _initializeStrictAppCheck() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
      webProvider: ReCaptchaV3Provider(
        const String.fromEnvironment(
          'RECAPTCHA_SITE_KEY',
          defaultValue: 'recaptcha-v3-site-key',
        ),
      ),
    );
    debugPrint('Firebase App Check initialized');

    // getToken() has no SDK timeout; on some networks/devices each call can
    // block for minutes. Cap per attempt + total wait so startup cannot hang.
    const attempts = 3;
    const perAttemptTimeout = Duration(seconds: 12);
    const delaysMs = <int>[0, 400, 1000];
    for (var i = 0; i < attempts; i++) {
      if (delaysMs[i] > 0) {
        await Future<void>.delayed(Duration(milliseconds: delaysMs[i]));
      }
      String? token;
      try {
        token = await FirebaseAppCheck.instance
            .getToken(true)
            .timeout(
              perAttemptTimeout,
              onTimeout: () {
                debugPrint(
                  '⚠️ App Check getToken timed out (${perAttemptTimeout.inSeconds}s)',
                );
                return null;
              },
            );
      } catch (e) {
        debugPrint('⚠️ App Check getToken error: $e');
        token = null;
      }
      if (token != null && token.isNotEmpty) {
        debugPrint('✅ App Check token obtained. Firebase access allowed.');
        if (kDebugMode) {
          await _printAppCheckDemoLogs();
        }
        return true;
      }
      debugPrint('⚠️ App Check token empty (attempt ${i + 1}/$attempts)');
    }
    if (kDebugMode) {
      debugPrint(
        '⚠️ App Check token missing after retries — continuing in debug build. '
        'Common causes: no network, emulator DNS (UnknownHostException), or '
        'firebaseappcheck.googleapis.com unreachable. Firestore may return '
        'PERMISSION_DENIED until connectivity works; release builds still block.',
      );
      return true;
    }
    debugPrint(
      '❌ App Check token missing after retries. Blocking app startup.',
    );
    return false;
  } catch (e) {
    debugPrint('❌ App Check initialization/token failed: $e');
    return false;
  }
}

Future<void> _printAppCheckDemoLogs() async {
  try {
    final token = await FirebaseAppCheck.instance.getToken(true);
    if (token == null || token.isEmpty) {
      debugPrint('[AppCheck Demo] Token fetch returned empty.');
      return;
    }
    debugPrint(
      '[AppCheck Demo] Token fetched (first 24 chars): '
      '${token.substring(0, token.length > 24 ? 24 : token.length)}...',
    );
    debugPrint(
      '[AppCheck Demo] If using AndroidProvider.debug, copy the "debug secret" '
      'from native logs (look for "Enter this debug secret into the Firebase Console").',
    );
    debugPrint(
      '[AppCheck Demo] Add that debug secret in Firebase Console: '
      'Build > App Check > Your Android app > Manage debug tokens.',
    );
  } catch (e) {
    debugPrint('[AppCheck Demo] Failed to fetch App Check token: $e');
  }
}

class _AppCheckBlockedApp extends StatelessWidget {
  const _AppCheckBlockedApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 54,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 12),
                const Text(
                  'App Check verification failed',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  kDebugMode
                      ? 'Add this device’s App Check debug token in the Firebase Console (App Check → Manage debug tokens), then restart the app.'
                      : 'This usually means a weak network, Google Play services still starting, or Play Integrity could not run. Check your connection, update the Play Store app, and try again. If it keeps happening, confirm Play Integrity is enabled for this Android app in Firebase Console (release signing SHA-256 registered).',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  // This widget is the root of your application.

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  @override
  Widget build(BuildContext context) {
    return OverlaySupport(
      child: ScreenUtilInit(
        designSize: const Size(360, 650),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) => MaterialApp(
          navigatorKey: MyApp.navigatorKey,
          navigatorObservers: [FirebaseAnalyticsObserver(analytics: analytics)],
          debugShowCheckedModeBanner: false,
          title: appName,
          theme: theme(),
          initialRoute: SplashScreen.routeName,
          routes: routes,
          builder: (context, child) {
            SizeConfig.init(context);
            return child!;
          },
        ),
      ),
    );
  }
}
