import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v23 includes subtrip columns and tables', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 23);

    final now = DateTime.utc(2026, 6, 21);
    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value('trip-1'),
        name: const Value('Japan'),
        destination: const Value('Tokyo'),
        ownerId: const Value('user-1'),
        baseCurrency: const Value('EUR'),
        subtripsEnabled: const Value(true),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await db.upsertSubtrip(
      LocalSubtripsCompanion(
        id: const Value('subtrip-1'),
        tripId: const Value('trip-1'),
        name: const Value('Tokyo crew'),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
      ),
    );
    await db.upsertSubtripMember(
      const LocalSubtripMembersCompanion(
        subtripId: Value('subtrip-1'),
        userId: Value('user-2'),
      ),
    );
    await db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('plan-1'),
        tripId: const Value('trip-1'),
        subtripId: const Value('subtrip-1'),
        kind: const Value('visit'),
        title: const Value('Ghibli Museum'),
        position: const Value(0),
        createdBy: const Value('user-2'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    final trip = await db.watchTrip('trip-1').first;
    final subtrips = await db.watchTripSubtrips('trip-1').first;
    final members = await db.watchTripSubtripMembers('trip-1').first;
    final planItems = await db.watchTripPlanItems('trip-1').first;

    expect(trip?.subtripsEnabled, isTrue);
    expect(subtrips.single.name, 'Tokyo crew');
    expect(members.single.userId, 'user-2');
    expect(planItems.single.subtripId, 'subtrip-1');
  });

  test('v22 to v23 migration adds subtrip mirrors', () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await db.customStatement('DROP TABLE IF EXISTS local_subtrip_members');
    await db.customStatement('DROP TABLE IF EXISTS local_subtrips');
    await db.customStatement(
      'ALTER TABLE local_plan_items DROP COLUMN subtrip_id',
    );
    await db.customStatement(
      'ALTER TABLE local_trips DROP COLUMN subtrips_enabled',
    );
    await db.customStatement('PRAGMA user_version = 22');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 22, 23);

    final tripColumns = await db.customSelect(
      "select * from pragma_table_info('local_trips')",
      readsFrom: {db.localTrips},
    ).get();
    final planColumns = await db.customSelect(
      "select * from pragma_table_info('local_plan_items')",
      readsFrom: {db.localPlanItems},
    ).get();
    final subtripTables = await db
        .customSelect(
          "select name from sqlite_master where type = 'table' and name in "
          "('local_subtrips', 'local_subtrip_members')",
        )
        .get();

    expect(
      tripColumns.map((row) => row.data['name']),
      contains('subtrips_enabled'),
    );
    expect(
      planColumns.map((row) => row.data['name']),
      contains('subtrip_id'),
    );
    expect(subtripTables, hasLength(2));
  });
}
