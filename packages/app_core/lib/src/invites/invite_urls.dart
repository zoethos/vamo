/// Invite link shapes for Wave 1 (web universal + app custom scheme).
abstract final class InviteUrls {
  static const webHost = 'vamo.world';

  /// Legacy host — still accepted when parsing old shared links.
  static const legacyWebHosts = ['vamo.app'];

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

  /// QR payload for in-person invite (R9) — owned-domain web link (S25 site).
  static String qrInvitePayload(String token) => webInviteLink(token);

  /// In-app route used by GoRouter after [parseToken].
  static String inAppJoinLocation(String token) =>
      '/join?token=${Uri.encodeQueryComponent(token)}';

  /// Extracts invite token from a scanned or pasted invite URL string.
  static String? parseTokenFromString(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    return parseToken(uri);
  }

  /// Extracts invite token from web or app invite URIs.
  static String? parseToken(Uri uri) {
    if (uri.scheme == appScheme && uri.host == appJoinHost) {
      return _nonEmpty(uri.queryParameters['token']);
    }

    final host = uri.host.toLowerCase();
    if (_isWebInviteHost(host)) {
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

  static bool _isWebInviteHost(String host) {
    if (host == webHost || host.endsWith('.$webHost')) return true;
    for (final legacy in legacyWebHosts) {
      if (host == legacy || host.endsWith('.$legacy')) return true;
    }
    return false;
  }

  static String? _nonEmpty(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
