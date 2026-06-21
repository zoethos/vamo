import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:feature_split/feature_split.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'crash_reporting.dart';
import 'push/firebase_push_registrar.dart';

void main() {
  runZonedGuarded<Future<void>>(_runVamoApp, (error, stackTrace) {
    CrashReporting.recordFatal(error, stackTrace);
    reportAndLog(
      error,
      stackTrace,
      screen: 'app_lifecycle',
      action: 'uncaught_zone_error',
      severity: ActionFailureSeverity.failure,
    );
  });
}

Future<void> _runVamoApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  await Env.load();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp();
      await CrashReporting.initialize();
    } catch (error, stackTrace) {
      // Replace app/android/app/google-services.json for real FCM (see RUN.md).
      reportAndLog(
        error,
        stackTrace,
        screen: 'app_lifecycle',
        action: 'firebase_initialize',
        severity: ActionFailureSeverity.degraded,
      );
    }
  }
  await initPostHog();
  await initializeVamoDateFormatting();
  // detectSessionInUri defaults true — supabase_flutter exchanges PKCE from
  // app.vamo://login-callback; AuthCallbackScreen only waits for signedIn.
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );

  runApp(
    ProviderScope(
      overrides: [
        remoteSyncGatewayProvider.overrideWith(
          (ref) => TripsRemoteSyncGateway(ref.watch(tripsRepositoryProvider)),
        ),
        pushRegistrarProvider.overrideWithValue(FirebasePushRegistrar()),
      ],
      child: const VamoApp(),
    ),
  );
}
