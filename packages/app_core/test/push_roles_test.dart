import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PushNotificationRoute parses data.route', () {
    expect(
      PushNotificationRoute.fromData({'route': '/trips/abc-123'}),
      '/trips/abc-123',
    );
    expect(PushNotificationRoute.fromData({'route': ''}), isNull);
    expect(PushNotificationRoute.fromData({}), isNull);
  });

  test('TripMemberRoles labels', () {
    expect(TripMemberRoles.label(TripMemberRoles.coAdmin), 'Co-admin');
    expect(TripMemberRoles.isCoAdmin('co-admin'), isTrue);
    expect(TripMemberRoles.isOwner('owner'), isTrue);
  });
}
