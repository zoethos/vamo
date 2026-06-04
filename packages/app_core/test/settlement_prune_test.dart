import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> seedSettlement({
    required String id,
    required String tripId,
  }) {
    return db.upsertSettlement(
      LocalSettlementsCompanion(
        id: Value(id),
        tripId: Value(tripId),
        fromUser: const Value('user-a'),
        toUser: const Value('user-b'),
        amountCents: const Value(1000),
        currency: const Value('EUR'),
        status: const Value('marked'),
        createdAt: Value(DateTime.utc(2026, 6, 1)),
      ),
    );
  }

  test('pruneSettlementsForTrip removes rows absent from server response', () async {
    const tripId = 'trip-1';
    await seedSettlement(id: 's-local', tripId: tripId);
    await seedSettlement(id: 's-remote', tripId: tripId);

    await db.pruneSettlementsForTrip(tripId, {'s-remote'});

    final rows = await db.watchTripSettlements(tripId).first;
    expect(rows.map((r) => r.id), ['s-remote']);
  });

  test('pruneSettlementsForTrip preserves pending outbox settlement ids', () async {
    const tripId = 'trip-1';
    await seedSettlement(id: 's-pending', tripId: tripId);

    await db.pruneSettlementsForTrip(
      tripId,
      const {},
      excludeIds: {'s-pending'},
    );

    final rows = await db.watchTripSettlements(tripId).first;
    expect(rows.single.id, 's-pending');
  });
}
