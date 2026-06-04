import 'package:flutter/foundation.dart';

/// Supabase auth redirect URIs and helpers for deep-link handling.
abstract final class AuthUrls {
  static const appScheme = 'app.vamo';
  static const loginCallbackHost = 'login-callback';
  static const loginCallbackPath = '/login-callback';

  /// Platform-specific redirect registered in Supabase Auth → URL Configuration.
  ///
  /// Web must return to the same browser (PKCE verifier lives there). Mobile
  /// uses the custom scheme deep link.
  static String get redirectUri {
    if (kIsWeb) {
      return '${Uri.base.origin}$loginCallbackPath';
    }
    return '$appScheme://$loginCallbackHost';
  }

  static bool isAuthCallback(Uri uri) {
    if (uri.scheme == appScheme && uri.host == loginCallbackHost) {
      return true;
    }
    final path = uri.path;
    return path == loginCallbackPath || path == '$loginCallbackPath/';
  }

  /// Maps an auth redirect URI to an in-app GoRouter location.
  static String inAppLoginCallbackLocation(Uri uri) {
    if (uri.query.isEmpty) return loginCallbackPath;
    return '$loginCallbackPath?${uri.query}';
  }
}
