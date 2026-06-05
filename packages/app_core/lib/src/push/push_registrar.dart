import 'dart:async';

/// Platform push registration (FCM). Overridden in the app shell with Firebase.
abstract class PushRegistrar {
  /// Start listening for tokens and notification taps.
  /// [onRoute] receives in-app paths such as `/trips/<id>`.
  /// [onToken] receives FCM registration tokens — never log invite tokens.
  Future<void> start({
    required void Function(String route) onRoute,
    required void Function(String token) onToken,
  });

  Future<void> stop();
}
