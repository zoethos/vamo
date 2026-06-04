import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks in the Slice 1 guarantee: trip + owner row survive a DB round-trip.
void main() {
  test('trip and owner membership persist in Drift', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final now = DateTime.utc(2026, 6, 2);
    const tripId = 'trip-test-1';
    const userId = 'user-test-1';

    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value(tripId),
        name: const Value('Amalfi'),
        ownerId: const Value(userId),
        baseCurrency: const Value('EUR'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await db.upsertMember(
      LocalTripMembersCompanion(
        tripId: const Value(tripId),
        userId: const Value(userId),
        role: const Value('owner'),
        status: const Value('active'),
      ),
    );

    final trips = await db.watchAllTrips().first;
    expect(trips, hasLength(1));
    expect(trips.single.name, 'Amalfi');

    final members = await db.watchActiveMembers(tripId).first;
    expect(members, hasLength(1));
    expect(members.single.role, 'owner');
  });
}
