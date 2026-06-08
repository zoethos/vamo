import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// FCM registration + notification tap routing (Android-first T10.5).
class FirebasePushRegistrar implements PushRegistrar {
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _openSub;
  void Function(String route)? _onRoute;

  @override
  Future<void> start({
    required void Function(String route) onRoute,
    required void Function(String token) onToken,
  }) async {
    _onRoute = onRoute;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'push',
        action: 'request_permission',
        severity: ActionFailureSeverity.degraded,
      );
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    _dispatch(initial);

    _openSub ??= FirebaseMessaging.onMessageOpenedApp.listen(_dispatch);

    _tokenSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(onToken);

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) onToken(token);
  }

  void _dispatch(RemoteMessage? message) {
    if (message == null) return;
    final route = PushNotificationRoute.fromData(message.data);
    if (route != null) _onRoute?.call(route);
  }

  @override
  Future<void> stop() async {
    await _tokenSub?.cancel();
    _tokenSub = null;
    await _openSub?.cancel();
    _openSub = null;
    _onRoute = null;
  }
}

/// Required top-level handler for background messages (no-op for now).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}
