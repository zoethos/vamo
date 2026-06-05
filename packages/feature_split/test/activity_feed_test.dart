import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:feature_split/feature_split.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('activity feed orders newest first and groups by day', () async {
    final tripId = 'trip-a';
    final created = DateTime.utc(2026, 1, 1);
    await db.upsertTrip(
      LocalTripsCompanion(
        id: Value(tripId),
        name: const Value('Rome'),
        baseCurrency: const Value('EUR'),
        ownerId: const Value('u1'),
        createdAt: Value(created),
        updatedAt: Value(created),
      ),
    );

    final older = DateTime.utc(2026, 6, 1, 10);
    final newer = DateTime.utc(2026, 6, 2, 12);

    await db.upsertExpense(
      LocalExpensesCompanion(
        id: const Value('e-old'),
        tripId: Value(tripId),
        description: const Value('Coffee'),
        amountCents: const Value(300),
        baseCents: const Value(300),
        currency: const Value('EUR'),
        payerId: const Value('u1'),
        fxRate: const Value(1.0),
        spentAt: Value(older),
        createdBy: const Value('u1'),
        createdAt: Value(older),
      ),
    );
    await db.upsertExpense(
      LocalExpensesCompanion(
        id: const Value('e-new'),
        tripId: Value(tripId),
        description: const Value('Dinner'),
        amountCents: const Value(5000),
        baseCents: const Value(5000),
        currency: const Value('EUR'),
        payerId: const Value('u1'),
        fxRate: const Value(1.0),
        spentAt: Value(newer),
        createdBy: const Value('u1'),
        createdAt: Value(newer),
      ),
    );

    final items = await _buildFeed(db);
    expect(items.first.title, 'Dinner');
    expect(items.last.title, 'Coffee');

    final grouped = groupActivityByDay(items);
    expect(grouped.length, 2);
    expect(grouped[DateTime.utc(2026, 6, 2)]!.length, 1);
  });
}

Future<List<ActivityItem>> _buildFeed(AppDatabase db) async {
  // Mirror private builder from activity_repository for unit testing.
  final trips = await db.select(db.localTrips).get();
  final tripNames = {for (final t in trips) t.id: t.name};
  final expenses = await db.select(db.localExpenses).get();
  final items = expenses
      .map(
        (e) => ActivityItem(
          id: 'expense_${e.id}',
          tripId: e.tripId,
          tripName: tripNames[e.tripId] ?? 'Trip',
          kind: ActivityKind.expense,
          title: e.description,
          subtitle: 'Expense added',
          occurredAt: e.createdAt,
        ),
      )
      .toList()
    ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  return items;
}
