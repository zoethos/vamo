import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('background columns on trips do not create trip_photos rows', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const tripId = 'trip-1';
    final now = DateTime.utc(2026, 6, 5);
    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value(tripId),
        name: const Value('Amalfi'),
        ownerId: const Value('user-1'),
        baseCurrency: const Value('EUR'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value(tripId),
        name: const Value('Amalfi'),
        ownerId: const Value('user-1'),
        baseCurrency: const Value('EUR'),
        backgroundLocalPath: const Value('/data/trip-backgrounds/trip-1/hero.jpg'),
        backgroundPath: const Value('user-1/trip-1/background.jpg'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    final trip = await db.watchTrip(tripId).first;
    expect(trip?.backgroundLocalPath, '/data/trip-backgrounds/trip-1/hero.jpg');
    expect(trip?.backgroundPath, 'user-1/trip-1/background.jpg');

    final photos = await db.watchTripPhotos(tripId).first;
    expect(photos, isEmpty);
  });
}
