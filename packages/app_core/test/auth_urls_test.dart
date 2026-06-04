import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects app-scheme auth callback deep link', () {
    expect(
      AuthUrls.isAuthCallback(
        Uri.parse('app.vamo://login-callback/?code=abc'),
      ),
      isTrue,
    );
  });

  test('detects web auth callback path', () {
    expect(
      AuthUrls.isAuthCallback(
        Uri.parse('http://localhost:3000/login-callback?code=abc'),
      ),
      isTrue,
    );
  });

  test('maps auth callback to in-app route', () {
    expect(
      AuthUrls.inAppLoginCallbackLocation(
        Uri.parse('app.vamo://login-callback/?code=abc'),
      ),
      '/login-callback?code=abc',
    );
  });

  test('mobile redirect URI uses custom scheme', () {
    expect(AuthUrls.redirectUri, 'app.vamo://login-callback');
  });
}
