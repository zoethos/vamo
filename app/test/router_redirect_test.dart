import 'package:app_core/app_core.dart';
import 'package:feature_split/feature_split.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vamo/router_redirect.dart';

void main() {
  group('resolveRouterRedirect', () {
    test('maps app join deep link to in-app join when signed in', () {
      final uri = Uri.parse('app.vamo://join/-?token=abc');

      expect(
        resolveRouterRedirect(
          uri: uri,
          matchedLocation: uri.toString(),
          queryParameters: uri.queryParameters,
          isSignedIn: true,
        ),
        InviteUrls.inAppJoinLocation('abc'),
      );
    });

    test('maps app join deep link to /auth with pending token when signed out', () {
      final uri = Uri.parse('app.vamo://join/-?token=abc');

      final normalized = resolveRouterRedirect(
        uri: uri,
        matchedLocation: uri.toString(),
        queryParameters: uri.queryParameters,
        isSignedIn: false,
      );
      expect(normalized, InviteUrls.inAppJoinLocation('abc'));

      String? pendingToken;
      InviteChannel? pendingChannel;
      expect(
        resolveRouterRedirect(
          uri: Uri.parse(InviteUrls.inAppJoinLocation('abc')),
          matchedLocation: AppRoutes.join,
          queryParameters: const {'token': 'abc'},
          isSignedIn: false,
          onPendingInvite: (token, channel) {
            pendingToken = token;
            pendingChannel = channel;
          },
        ),
        AppRoutes.auth,
      );
      expect(pendingToken, 'abc');
      expect(pendingChannel, InviteChannel.link);
    });

    test('preserves contact channel on signed-out join redirect', () {
      InviteChannel? pendingChannel;
      resolveRouterRedirect(
        uri: Uri.parse('https://vamo.world/j/tok'),
        matchedLocation: AppRoutes.join,
        queryParameters: const {'token': 'tok', 'ch': 'contact'},
        isSignedIn: false,
        onPendingInvite: (_, channel) => pendingChannel = channel,
      );
      expect(pendingChannel, InviteChannel.contact);
    });

    test('unknown ch defaults to link on signed-out join redirect', () {
      InviteChannel? pendingChannel;
      resolveRouterRedirect(
        uri: Uri.parse('https://vamo.world/j/tok'),
        matchedLocation: AppRoutes.join,
        queryParameters: const {'token': 'tok', 'ch': 'bogus'},
        isSignedIn: false,
        onPendingInvite: (_, channel) => pendingChannel = channel,
      );
      expect(pendingChannel, InviteChannel.link);
    });

    test('accepts join path shapes on custom scheme host', () {
      for (final raw in [
        'app.vamo://join?token=t',
        'app.vamo://join/?token=t',
        'app.vamo://join/-?token=t',
        'app.vamo://join/extra?token=t',
      ]) {
        final uri = Uri.parse(raw);
        expect(
          resolveRouterRedirect(
            uri: uri,
            matchedLocation: raw,
            queryParameters: uri.queryParameters,
            isSignedIn: true,
          ),
          InviteUrls.inAppJoinLocation('t'),
          reason: raw,
        );
      }
    });

    test('maps auth callback on custom scheme', () {
      final uri = Uri.parse('app.vamo://login-callback?code=abc');

      expect(
        resolveRouterRedirect(
          uri: uri,
          matchedLocation: uri.toString(),
          queryParameters: uri.queryParameters,
          isSignedIn: false,
        ),
        AuthUrls.inAppLoginCallbackLocation(uri),
      );
    });
  });
}
