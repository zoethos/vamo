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

    const collectionEnabled = !kDebugMode;
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      collectionEnabled,
    );
    _enabled = collectionEnabled;

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (previousFlutterError != null) {
        previousFlutterError(details);
      } else {
        FlutterError.presentError(details);
      }
      if (_enabled) {
        unawaited(
          FirebaseCrashlytics.instance.recordFlutterError(details),
        );
      }
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
