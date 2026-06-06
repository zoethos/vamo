import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trip realtime listens to plan and list tables for peer refresh', () {
    expect(
      TripRealtimeSubscriber.tablesFilteredByTripId,
      containsAll([
        'trip_plan_items',
        'trip_list_items',
        'expenses',
      ]),
    );
  });
}
