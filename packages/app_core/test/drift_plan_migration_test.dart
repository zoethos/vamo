import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v13 includes plan, governance, budget, and rsvp tables',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 24);

    final now = DateTime.utc(2026, 6, 5);
    await db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('plan-1'),
        tripId: const Value('trip-1'),
        kind: const Value('lodging'),
        title: const Value('Hotel'),
        metadata: const Value('{"booking":"ABC123"}'),
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
    expect(plans.single.metadata, '{"booking":"ABC123"}');
    expect(lists, hasLength(1));
  });

  test('v9 to v13 migration step creates plan, governance, budget, and rsvp',
      () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await db.customStatement('DROP TABLE IF EXISTS local_plan_items');
    await db.customStatement('DROP TABLE IF EXISTS local_trip_list_items');
    await db.customStatement('DROP TABLE IF EXISTS local_trip_fx_rates');
    await db.customStatement('DROP TABLE IF EXISTS local_plan_item_rsvps');
    await db.customStatement('ALTER TABLE local_expenses DROP COLUMN status');
    await db.customStatement(
        'ALTER TABLE local_expense_shares DROP COLUMN response');
    await db.customStatement(
      'ALTER TABLE local_expense_shares DROP COLUMN response_reason',
    );
    await db.customStatement(
      'ALTER TABLE local_expense_shares DROP COLUMN responded_at',
    );
    await db.customStatement('ALTER TABLE local_trips DROP COLUMN budget_mode');
    await db
        .customStatement('ALTER TABLE local_trips DROP COLUMN budget_cents');
    await db.customStatement('PRAGMA user_version = 9');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 9, 13);

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

  test('v19 to v20 migration adds plan item metadata column', () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await db
        .customStatement('ALTER TABLE local_plan_items DROP COLUMN metadata');
    await db.customStatement('PRAGMA user_version = 19');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 19, 20);

    final now = DateTime.utc(2026, 6, 19);
    await db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('plan-meta'),
        tripId: const Value('trip-1'),
        kind: const Value('activity'),
        title: const Value('Dinner'),
        position: const Value(0),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    final plans = await db.watchTripPlanItems('trip-1').first;
    expect(plans.single.metadata, '{}');
  });
}
