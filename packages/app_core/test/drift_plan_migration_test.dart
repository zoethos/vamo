import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v11 includes plan and expense governance columns', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 11);

    final now = DateTime.utc(2026, 6, 5);
    await db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('plan-1'),
        tripId: const Value('trip-1'),
        kind: const Value('lodging'),
        title: const Value('Hotel'),
        position: const Value(0),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await db.upsertListItem(
      LocalTripListItemsCompanion(
        id: const Value('list-1'),
        tripId: const Value('trip-1'),
        listName: const Value('Packing'),
        label: const Value('Sunscreen'),
        position: const Value(0),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
      ),
    );

    final plans = await db.watchTripPlanItems('trip-1').first;
    final lists = await db.watchTripListItems('trip-1').first;
    expect(plans, hasLength(1));
    expect(lists, hasLength(1));
  });

  test('v9 to v11 migration step creates plan and governance columns', () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await db.customStatement('DROP TABLE IF EXISTS local_plan_items');
    await db.customStatement('DROP TABLE IF EXISTS local_trip_list_items');
    await db.customStatement('ALTER TABLE local_expenses DROP COLUMN status');
    await db.customStatement('ALTER TABLE local_expense_shares DROP COLUMN response');
    await db.customStatement(
      'ALTER TABLE local_expense_shares DROP COLUMN response_reason',
    );
    await db.customStatement(
      'ALTER TABLE local_expense_shares DROP COLUMN responded_at',
    );
    await db.customStatement('PRAGMA user_version = 9');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 9, 11);

    final now = DateTime.utc(2026, 6, 5);
    await db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('plan-1'),
        tripId: const Value('trip-1'),
        kind: const Value('lodging'),
        title: const Value('Hotel'),
        position: const Value(0),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    final plans = await db.watchTripPlanItems('trip-1').first;
    expect(plans, hasLength(1));
  });
}
