import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses web invite path', () {
    final token = InviteUrls.parseToken(
      Uri.parse('https://vamo.world/j/abc%2Bdef'),
    );
    expect(token, 'abc+def');
  });

  test('parses legacy vamo.app invite path', () {
    final token = InviteUrls.parseToken(
      Uri.parse('https://vamo.app/j/legacy-token'),
    );
    expect(token, 'legacy-token');
  });

  test('parses app invite scheme', () {
    final token = InviteUrls.parseToken(
      Uri.parse('app.vamo://join?token=xyz123'),
    );
    expect(token, 'xyz123');
  });

  test('parses app invite scheme with dash path segment', () {
    final token = InviteUrls.parseToken(
      Uri.parse('app.vamo://join/-?token=x'),
    );
    expect(token, 'x');
  });

  test('parses web invite from raw string', () {
    expect(
      InviteUrls.parseTokenFromString('https://vamo.world/j/tok-99'),
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
      'https://vamo.world/j/a%2Bb',
    );
  });

  test('qr payload uses owned web invite link', () {
    expect(InviteUrls.qrInvitePayload('tok'), InviteUrls.webInviteLink('tok'));
    expect(InviteUrls.qrInvitePayload('tok'), contains('vamo.world'));
  });

  test('web invite link adds ch=contact when requested', () {
    expect(
      InviteUrls.webInviteLink('tok', channel: 'contact'),
      'https://vamo.world/j/tok?ch=contact',
    );
  });

  test('web invite link omits ch for link channel', () {
    expect(InviteUrls.webInviteLink('tok'), 'https://vamo.world/j/tok');
    expect(InviteUrls.webInviteLink('tok', channel: 'link'), 'https://vamo.world/j/tok');
  });

  test('inAppJoinLocation carries contact channel', () {
    expect(
      InviteUrls.inAppJoinLocation('tok', channel: 'contact'),
      '/join?token=tok&ch=contact',
    );
  });

  test('channelQuery reads ch from invite URI', () {
    expect(
      InviteUrls.channelQuery(Uri.parse('https://vamo.world/j/tok?ch=contact')),
      'contact',
    );
    expect(
      InviteUrls.channelQuery(Uri.parse('https://vamo.world/j/tok')),
      isNull,
    );
  });
}
