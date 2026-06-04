import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses web invite path', () {
    final token = InviteUrls.parseToken(
      Uri.parse('https://vamo.app/j/abc%2Bdef'),
    );
    expect(token, 'abc+def');
  });

  test('parses app invite scheme', () {
    final token = InviteUrls.parseToken(
      Uri.parse('app.vamo://join?token=xyz123'),
    );
    expect(token, 'xyz123');
  });

  test('builds shareable web link', () {
    expect(
      InviteUrls.webInviteLink('a+b'),
      'https://vamo.app/j/a%2Bb',
    );
  });
}
