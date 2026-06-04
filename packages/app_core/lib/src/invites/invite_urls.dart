/// Invite link shapes for Wave 1 (web universal + app custom scheme).
abstract final class InviteUrls {
  static const webHost = 'vamo.app';
  static const webPathPrefix = '/j/';
  static const appScheme = 'app.vamo';
  static const appJoinHost = 'join';

  /// Shareable HTTPS link (store / web fallback when app not installed).
  static String webInviteLink(String token) =>
      'https://$webHost$webPathPrefix${Uri.encodeComponent(token)}';

  /// Opens the app when installed (`app.vamo://join?token=…`).
  static Uri appInviteUri(String token) => Uri(
        scheme: appScheme,
        host: appJoinHost,
        queryParameters: {'token': token},
      );

  /// In-app route used by GoRouter after [parseToken].
  static String inAppJoinLocation(String token) =>
      '/join?token=${Uri.encodeQueryComponent(token)}';

  /// Extracts invite token from web or app invite URIs.
  static String? parseToken(Uri uri) {
    if (uri.scheme == appScheme && uri.host == appJoinHost) {
      return _nonEmpty(uri.queryParameters['token']);
    }

    final host = uri.host.toLowerCase();
    if (host == webHost || host.endsWith('.$webHost')) {
      final segments = uri.pathSegments;
      if (segments.length >= 2 && segments.first == 'j') {
        return _nonEmpty(Uri.decodeComponent(segments[1]));
      }
      if (segments.length == 1 && segments.first == 'j') {
        return _nonEmpty(uri.queryParameters['token']);
      }
    }

    return null;
  }

  static String? _nonEmpty(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
