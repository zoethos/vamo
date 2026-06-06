import 'package:feature_split/src/invites/invite_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contact analytics value is contact', () {
    expect(InviteChannel.contact.analyticsValue, 'contact');
  });

  test('fromQuery maps contact channel', () {
    expect(InviteChannel.fromQuery('contact'), InviteChannel.contact);
  });

  test('fromQuery defaults missing channel to link', () {
    expect(InviteChannel.fromQuery(null), InviteChannel.link);
    expect(InviteChannel.fromQuery(''), InviteChannel.link);
  });

  test('fromQuery defaults unknown channel to link', () {
    expect(InviteChannel.fromQuery('qr-code'), InviteChannel.link);
    expect(InviteChannel.fromQuery('token'), InviteChannel.link);
  });
}
