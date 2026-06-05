import 'package:app_core/app_core.dart';
import 'package:feature_split/feature_split.dart';

/// Pure redirect rule for [routerProvider] — testable without GoRouter.
///
/// Normalizes `app.vamo://…` custom-scheme URIs to in-app paths before auth
/// and invite handling (defense in depth when engine-level deep linking is off).
String? resolveRouterRedirect({
  required Uri uri,
  required String matchedLocation,
  required Map<String, String> queryParameters,
  required bool isSignedIn,
  void Function(String token)? onPendingInvite,
}) {
  if (uri.scheme == AuthUrls.appScheme) {
    if (AuthUrls.isAuthCallback(uri)) {
      return AuthUrls.inAppLoginCallbackLocation(uri);
    }
    if (uri.host == InviteUrls.appJoinHost) {
      return InviteUrls.inAppJoinLocation(
        uri.queryParameters['token'] ?? '',
      );
    }
  }

  if (matchedLocation.startsWith('${AuthUrls.appScheme}://')) {
    final parsed = Uri.tryParse(matchedLocation);
    if (parsed != null) {
      if (AuthUrls.isAuthCallback(parsed)) {
        return AuthUrls.inAppLoginCallbackLocation(parsed);
      }
      if (parsed.host == InviteUrls.appJoinHost) {
        return InviteUrls.inAppJoinLocation(
          parsed.queryParameters['token'] ?? '',
        );
      }
    }
  }

  final token = inviteTokenFromLocation(
    matchedLocation,
    query: queryParameters,
  );
  if (token != null && !isSignedIn) {
    onPendingInvite?.call(token);
    return AppRoutes.auth;
  }

  return authRedirect(isSignedIn: isSignedIn, location: matchedLocation);
}
