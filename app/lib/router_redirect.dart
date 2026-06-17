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
  bool profileRequiresCompletion = false,
  void Function(String token, InviteChannel channel)? onPendingInvite,
}) {
  if (uri.scheme == AuthUrls.appScheme) {
    if (AuthUrls.isAuthCallback(uri)) {
      return AuthUrls.inAppLoginCallbackLocation(uri);
    }
    if (uri.host == InviteUrls.appJoinHost) {
      return InviteUrls.inAppJoinLocation(
        uri.queryParameters['token'] ?? '',
        channel: uri.queryParameters['ch'],
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
          channel: parsed.queryParameters['ch'],
        );
      }
    }
  }

  final token = inviteTokenFromLocation(
    matchedLocation,
    query: queryParameters,
  );
  if (token != null && !isSignedIn) {
    onPendingInvite?.call(
      token,
      inviteChannelFromQuery(queryParameters),
    );
    return AppRoutes.auth;
  }

  final authTarget = authRedirect(
    isSignedIn: isSignedIn,
    location: matchedLocation,
  );
  if (authTarget != null) return authTarget;
  if (!isSignedIn || matchedLocation.startsWith(AppRoutes.loginCallback)) {
    return null;
  }

  final onCompletionRoute = matchedLocation == AppRoutes.profileCompletion;
  if (profileRequiresCompletion) {
    if (onCompletionRoute || matchedLocation == AppRoutes.join) return null;
    return AppRoutes.profileCompletion;
  }
  if (onCompletionRoute) return AppRoutes.trips;
  return null;
}
