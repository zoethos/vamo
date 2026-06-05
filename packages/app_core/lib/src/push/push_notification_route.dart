/// Parses push notification data into an in-app GoRouter location.
abstract final class PushNotificationRoute {
  /// FCM `data.route` — e.g. `/trips/<uuid>` or `/join?token=…`.
  static String? fromData(Map<String, dynamic> data) {
    final raw = data['route'];
    if (raw is! String) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('/')) return null;
    return trimmed;
  }
}
