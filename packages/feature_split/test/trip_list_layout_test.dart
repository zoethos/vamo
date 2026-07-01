import 'package:feature_split/src/trips/trip_list_layout.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('layoutTripsForMyTrips picks soonest upcoming as featured', () {
    final layout = layoutTripsForMyTrips([
      const TripSummary(
        id: 'b',
        name: 'Later',
        startDate: '2026-09-01',
        baseCurrency: 'EUR',
      ),
      const TripSummary(
        id: 'a',
        name: 'Soonest',
        startDate: '2026-07-01',
        baseCurrency: 'EUR',
      ),
    ], now: DateTime.utc(2026, 6, 30));

    expect(layout.featured?.id, 'a');
    expect(layout.upcoming, hasLength(1));
    expect(layout.upcoming.single.id, 'b');
  });
}
