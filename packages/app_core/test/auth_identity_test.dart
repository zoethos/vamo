import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthIdentityProvider', () {
    test('recognizes only Vamo supported methods', () {
      expect(
        AuthIdentityProvider.fromSupabaseProvider('email'),
        AuthIdentityProvider.email,
      );
      expect(
        AuthIdentityProvider.fromSupabaseProvider('google'),
        AuthIdentityProvider.google,
      );
      expect(
        AuthIdentityProvider.fromSupabaseProvider('apple'),
        AuthIdentityProvider.apple,
      );
      expect(AuthIdentityProvider.fromSupabaseProvider('phone'), isNull);
      expect(AuthIdentityProvider.fromSupabaseProvider(null), isNull);
    });

    test('uses the provider identity rather than an OAuth email', () {
      expect(AuthIdentityProvider.apple.supabaseProvider, 'apple');
      expect(AuthIdentityProvider.google.supabaseProvider, 'google');
    });
  });
}
