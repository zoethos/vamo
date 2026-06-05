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

  test('parses web invite from raw string', () {
    expect(
      InviteUrls.parseTokenFromString('https://vamo.app/j/tok-99'),
      'tok-99',
    );
  });

  test('parses app invite from raw string', () {
    expect(
      InviteUrls.parseTokenFromString('app.vamo://join?token=scan-me'),
      'scan-me',
    );
  });

  test('rejects garbage strings', () {
    expect(InviteUrls.parseTokenFromString('https://example.com/j/nope'), isNull);
    expect(InviteUrls.parseTokenFromString('not a url'), isNull);
    expect(InviteUrls.parseTokenFromString(''), isNull);
  });

  test('builds shareable web link', () {
    expect(
      InviteUrls.webInviteLink('a+b'),
      'https://vamo.app/j/a%2Bb',
    );
  });

  test('qr payload uses app scheme not web host', () {
    expect(
      InviteUrls.qrInvitePayload('tok'),
      'app.vamo://join?token=tok',
    );
    expect(InviteUrls.qrInvitePayload('tok'), isNot(contains('vamo.app')));
  });
}
