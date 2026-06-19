import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashReporting {
  CrashReporting._();

  static bool _enabled = false;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> initialize() async {
    if (!isSupported) return;

    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    _enabled = true;

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (previousFlutterError != null) {
        previousFlutterError(details);
      } else {
        FlutterError.presentError(details);
      }
      unawaited(
        FirebaseCrashlytics.instance.recordFlutterFatalError(details),
      );
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      recordFatal(error, stackTrace);
      return true;
    };
  }

  static void recordFatal(Object error, StackTrace stackTrace) {
    if (!_enabled) return;
    unawaited(
      FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        fatal: true,
      ),
    );
  }
}
