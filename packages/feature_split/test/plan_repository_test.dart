import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:feature_split/src/plan/plan_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('groupPlanItemsByDay puts undated items last', () {
    final items = [
      PlanItemSummary(
        id: '1',
        tripId: 't',
        kind: PlanItemKind.other,
        title: 'Undated',
        position: 0,
      ),
      PlanItemSummary(
        id: '2',
        tripId: 't',
        kind: PlanItemKind.flight,
        title: 'Day 1',
        startsAt: DateTime.utc(2026, 7, 1, 14),
        position: 1,
      ),
      PlanItemSummary(
        id: '3',
        tripId: 't',
        kind: PlanItemKind.lodging,
        title: 'Day 2',
        startsAt: DateTime.utc(2026, 7, 2, 9),
        position: 2,
      ),
    ];

    final grouped = groupPlanItemsByDay(items);
    expect(grouped, hasLength(3));
    expect(grouped.first.dayKey, '2026-07-01');
    expect(grouped.last.dayKey, isNull);
    expect(grouped.last.items.single.title, 'Undated');
  });

  test('plan item reorder swaps positions in drift', () async {
    const tripId = 'trip-plan';
    final now = DateTime.utc(2026, 6, 5);

    await db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('a'),
        tripId: const Value(tripId),
        kind: const Value('lodging'),
        title: const Value('A'),
        position: const Value(0),
        createdBy: const Value('u1'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('b'),
        tripId: const Value(tripId),
        kind: const Value('train'),
        title: const Value('B'),
        position: const Value(1),
        createdBy: const Value('u1'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    await db.upsertPlanItem(
      const LocalPlanItemsCompanion(
        id: Value('a'),
        position: Value(1),
      ),
    );
    await db.upsertPlanItem(
      const LocalPlanItemsCompanion(
        id: Value('b'),
        position: Value(0),
      ),
    );

    final rows = await db.watchTripPlanItems(tripId).first;
    expect(rows.firstWhere((r) => r.id == 'a').position, 1);
    expect(rows.firstWhere((r) => r.id == 'b').position, 0);
  });

  test('checklist toggle round-trip in drift', () async {
    const tripId = 'trip-plan';
    const userId = 'user-plan';
    final now = DateTime.utc(2026, 6, 5);

    await db.upsertListItem(
      LocalTripListItemsCompanion(
        id: const Value('list-1'),
        tripId: const Value(tripId),
        listName: const Value('Packing'),
        label: const Value('Sunscreen'),
        position: const Value(0),
        createdBy: const Value(userId),
        createdAt: Value(now),
      ),
    );

    await db.upsertListItem(
      LocalTripListItemsCompanion(
        id: const Value('list-1'),
        checkedBy: const Value(userId),
        checkedAt: Value(now),
      ),
    );
    var row = await db.watchTripListItems(tripId).first;
    expect(row.single.checkedBy, userId);

    await db.upsertListItem(
      const LocalTripListItemsCompanion(
        id: Value('list-1'),
        checkedBy: Value(null),
        checkedAt: Value(null),
      ),
    );
    row = await db.watchTripListItems(tripId).first;
    expect(row.single.checkedBy, isNull);
  });
}
