import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v12 includes budget and trip_fx_rates', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 22);

    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value('trip-budget'),
        name: const Value('Budget trip'),
        ownerId: const Value('owner'),
        baseCurrency: const Value('EUR'),
        budgetMode: const Value('formal'),
        budgetCents: const Value(50000),
        createdAt: Value(DateTime.utc(2026, 6, 5)),
        updatedAt: Value(DateTime.utc(2026, 6, 5)),
      ),
    );

    await db.upsertTripFxRate(
      LocalTripFxRatesCompanion(
        id: const Value('fx-1'),
        tripId: const Value('trip-budget'),
        currency: const Value('USD'),
        rate: const Value(0.92),
        source: const Value('exchangerate.host'),
        capturedAt: Value(DateTime.utc(2026, 6, 5)),
        capturedBy: const Value('owner'),
      ),
    );

    final trip = await db.select(db.localTrips).getSingle();
    expect(trip.budgetMode, 'formal');
    expect(trip.budgetCents, 50000);

    final rates = await db.select(db.localTripFxRates).get();
    expect(rates, hasLength(1));
    expect(rates.single.currency, 'USD');
  });
}
