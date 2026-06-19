import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v13 includes trip_plan_item_rsvps', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 21);

    final now = DateTime.utc(2026, 6, 5);
    await db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('event-1'),
        tripId: const Value('trip-1'),
        kind: const Value('activity'),
        title: const Value('Dinner'),
        position: const Value(0),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await db.upsertPlanItemRsvp(
      LocalPlanItemRsvpsCompanion(
        id: const Value('rsvp-1'),
        planItemId: const Value('event-1'),
        userId: const Value('user-1'),
        status: const Value('going'),
        respondedAt: Value(now),
      ),
    );

    final rows = await db.watchTripPlanItemRsvps('trip-1').first;
    expect(rows, hasLength(1));
    expect(rows.single.status, 'going');
  });

  test('v12 to v13 migration creates plan item rsvps table', () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await db.customStatement('DROP TABLE IF EXISTS local_plan_item_rsvps');
    await db.customStatement('PRAGMA user_version = 12');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 12, 13);

    final now = DateTime.utc(2026, 6, 5);
    await db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('event-1'),
        tripId: const Value('trip-1'),
        kind: const Value('activity'),
        title: const Value('Dinner'),
        position: const Value(0),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await db.upsertPlanItemRsvp(
      LocalPlanItemRsvpsCompanion(
        id: const Value('rsvp-1'),
        planItemId: const Value('event-1'),
        userId: const Value('user-1'),
        status: const Value('maybe'),
        respondedAt: Value(now),
      ),
    );

    final rows = await db.watchTripPlanItemRsvps('trip-1').first;
    expect(rows.single.status, 'maybe');
  });
}
