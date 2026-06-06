import 'package:app_core/app_core.dart';
import 'package:feature_split/src/invites/contact_invite_target.dart';
import 'package:feature_split/src/invites/invite_analytics.dart';
import 'package:feature_split/src/invites/invite_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _CapturingAnalytics analytics;

  setUp(() {
    analytics = _CapturingAnalytics();
  });

  test('member_invited link channel has no qr_shown', () {
    captureMemberInvitedShow(
      analytics,
      tripId: 'trip-1',
      channel: InviteChannel.link,
    );
    expect(analytics.events.length, 1);
    expect(analytics.events.first.$1, VamoEvent.memberInvited);
    expect(analytics.events.first.$2, {
      'trip_id': 'trip-1',
      'channel': 'link',
    });
  });

  test('member_invited qr channel also fires qr_shown', () {
    captureMemberInvitedShow(
      analytics,
      tripId: 'trip-2',
      channel: InviteChannel.qr,
    );
    expect(analytics.events.length, 2);
    expect(analytics.events[0].$1, VamoEvent.memberInvited);
    expect(analytics.events[0].$2['channel'], 'qr');
    expect(analytics.events[1].$1, VamoEvent.qrShown);
    expect(analytics.events[1].$2, {'trip_id': 'trip-2'});
  });

  test('invite_accepted carries channel without token', () {
    captureInviteAccepted(
      analytics,
      tripId: 'trip-3',
      channel: InviteChannel.qr,
    );
    expect(analytics.events.single.$2, {
      'trip_id': 'trip-3',
      'channel': 'qr',
    });
    expect(analytics.events.single.$2.containsKey('invite_token'), isFalse);
  });

  test('member_invited contact channel includes target_type only', () {
    captureMemberInvitedShow(
      analytics,
      tripId: 'trip-4',
      channel: InviteChannel.contact,
      targetType: ContactInviteTargetType.phone,
    );
    expect(analytics.events.single.$2, {
      'trip_id': 'trip-4',
      'channel': 'contact',
      'target_type': 'phone',
    });
    expect(analytics.events.single.$2.containsKey('phone'), isFalse);
    expect(analytics.events.single.$2.containsKey('token'), isFalse);
  });
}

class _CapturingAnalytics implements Analytics {
  final events = <(VamoEvent, Map<String, Object?>)>[];

  @override
  void capture(VamoEvent event, {Map<String, Object?> properties = const {}}) {
    events.add((event, Map<String, Object?>.from(properties)));
  }

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<void> reset() async {}
}
