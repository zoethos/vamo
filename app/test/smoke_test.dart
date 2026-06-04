import 'package:app_core/app_core.dart';
import 'package:feature_split/feature_split.dart';
import 'package:flutter_test/flutter_test.dart';

/// Slice 0 sanity checks for the pure auth-redirect rule. The widget/integration
/// flow is exercised manually against a live Supabase project (see RUN.md);
/// this guards the routing logic that decides auth vs. trips.
void main() {
  group('authRedirect', () {
    test('signed-out user is sent to /auth', () {
      expect(
        authRedirect(isSignedIn: false, location: AppRoutes.trips),
        AppRoutes.auth,
      );
    });

    test('signed-out user already on /auth stays', () {
      expect(
        authRedirect(isSignedIn: false, location: AppRoutes.auth),
        isNull,
      );
    });

    test('signed-in user is kept out of /auth', () {
      expect(
        authRedirect(isSignedIn: true, location: AppRoutes.auth),
        AppRoutes.trips,
      );
    });

    test('signed-in user on /trips stays', () {
      expect(
        authRedirect(isSignedIn: true, location: AppRoutes.trips),
        isNull,
      );
    });

    test('login callback is allowed while processing redirect', () {
      expect(
        authRedirect(
          isSignedIn: false,
          location: '${AppRoutes.loginCallback}?code=abc',
        ),
        isNull,
      );
    });
  });

  group('inviteTokenFromLocation', () {
    test('reads token from query', () {
      expect(
        inviteTokenFromLocation(
          '/join',
          query: {'token': 'abc123'},
        ),
        'abc123',
      );
    });

    test('reads token from path segment', () {
      expect(
        inviteTokenFromLocation('/join/abc%2Bdef'),
        'abc+def',
      );
    });
  });
}
