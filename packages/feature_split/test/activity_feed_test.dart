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

  test('activity feed orders newest first and groups by local day', () async {
    final tripId = 'trip-a';
    final created = DateTime.utc(2026, 1, 1);
    await _trip(db, tripId: tripId, name: 'Rome', createdAt: created);

    final older = DateTime.utc(2026, 6, 1, 10);
    final newer = DateTime.utc(2026, 6, 2, 12);

    await _expense(
      db,
      id: 'e-old',
      tripId: tripId,
      description: 'Coffee',
      amountCents: 300,
      at: older,
    );
    await _expense(
      db,
      id: 'e-new',
      tripId: tripId,
      description: 'Dinner',
      amountCents: 5000,
      at: newer,
    );

    final items = await buildActivityFeedForTest(db, currentUserId: 'u1');
    expect(items.first.title, 'You added Dinner');
    expect(items.last.title, 'You added Coffee');

    final grouped = groupActivityByDay(items);
    expect(grouped.length, 2);
    expect(grouped[DateTime(2026, 6, 2)]!.length, 1);
  });

  test('activity feed includes plan, RSVP, media, and lifecycle rows',
      () async {
    final tripId = 'trip-a';
    final tripCreated = DateTime.utc(2026, 6, 1);
    final closeAt = DateTime.utc(2026, 6, 6, 12);
    await _trip(
      db,
      tripId: tripId,
      name: 'Amalfi Coast',
      createdAt: tripCreated,
      closeRequestedAt: closeAt,
    );
    await db.upsertMember(
      LocalTripMembersCompanion(
        tripId: Value(tripId),
        userId: const Value('u2'),
        role: const Value('member'),
        status: const Value('active'),
        displayName: const Value('Sofia'),
        joinedAt: Value(DateTime.utc(2026, 6, 1, 12)),
      ),
    );

    final planAt = DateTime.utc(2026, 6, 2, 9);
    await db.into(db.localPlanItems).insertOnConflictUpdate(
          LocalPlanItemsCompanion.insert(
            id: 'p1',
            tripId: tripId,
            kind: 'visit',
            title: 'Villa Rufolo',
            createdBy: 'u2',
            createdAt: planAt,
            updatedAt: planAt,
          ),
        );
    await db.into(db.localPlanItemRsvps).insertOnConflictUpdate(
          LocalPlanItemRsvpsCompanion.insert(
            id: 'r1',
            planItemId: 'p1',
            userId: 'u1',
            status: 'going',
            respondedAt: DateTime.utc(2026, 6, 2, 10),
          ),
        );
    await db.upsertTripPhoto(
      LocalTripPhotosCompanion.insert(
        id: 'photo-1',
        tripId: tripId,
        capturedAt: DateTime.utc(2026, 6, 3, 12),
        createdBy: 'u2',
        createdAt: DateTime.utc(2026, 6, 3, 12),
      ),
    );
    await db.upsertTripPhoto(
      LocalTripPhotosCompanion.insert(
        id: 'photo-2',
        tripId: tripId,
        capturedAt: DateTime.utc(2026, 6, 3, 12, 2),
        createdBy: 'u2',
        createdAt: DateTime.utc(2026, 6, 3, 12, 2),
      ),
    );

    final items = await buildActivityFeedForTest(db, currentUserId: 'u1');

    expect(
      items.map((item) => item.kind),
      containsAll([
        ActivityKind.planItemAdded,
        ActivityKind.planRsvp,
        ActivityKind.memberJoined,
        ActivityKind.photosAdded,
        ActivityKind.lifecycle,
      ]),
    );
    expect(
      items
          .singleWhere((item) => item.kind == ActivityKind.planItemAdded)
          .title,
      'Sofia added a Visit · Villa Rufolo',
    );
    expect(
      items.singleWhere((item) => item.kind == ActivityKind.planRsvp).title,
      'You are Going to Villa Rufolo',
    );
    expect(
      items.singleWhere((item) => item.kind == ActivityKind.photosAdded).title,
      'Sofia added 2 photos',
    );
    expect(
      items.singleWhere((item) => item.kind == ActivityKind.memberJoined).route,
      AppRoutes.tripMembers(tripId),
    );
    expect(
      items.singleWhere((item) => item.kind == ActivityKind.lifecycle).route,
      AppRoutes.tripCloseReport(tripId),
    );
  });

  test('money rows deep-link and tone amounts for the current user', () async {
    final tripId = 'trip-a';
    final at = DateTime.utc(2026, 6, 2, 12);
    await _trip(db, tripId: tripId, name: 'Bali Escape', createdAt: at);
    await _expense(
      db,
      id: 'e1',
      tripId: tripId,
      description: 'Lunch',
      amountCents: 6400,
      at: at,
      payerId: 'u2',
      createdBy: 'u2',
    );
    await db.upsertExpenseShare(
      const LocalExpenseSharesCompanion(
        id: Value('s1'),
        expenseId: Value('e1'),
        userId: Value('u1'),
        shareCents: Value(3200),
      ),
    );

    final items = await buildActivityFeedForTest(db, currentUserId: 'u1');
    final expense = items.singleWhere((item) => item.id == 'expense_e1');

    expect(expense.route, AppRoutes.tripExpenses(tripId));
    expect(expense.amountCents, 3200);
    expect(expense.amountTone, ActivityAmountTone.negative);
    expect(expense.filter, ActivityFilter.money);
  });
}

Future<void> _trip(
  AppDatabase db, {
  required String tripId,
  required String name,
  required DateTime createdAt,
  DateTime? closeRequestedAt,
}) async {
  await db.upsertTrip(
    LocalTripsCompanion(
      id: Value(tripId),
      name: Value(name),
      baseCurrency: const Value('EUR'),
      ownerId: const Value('u1'),
      closeRequestedAt: Value(closeRequestedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(closeRequestedAt ?? createdAt),
    ),
  );
  await db.upsertMember(
    LocalTripMembersCompanion(
      tripId: Value(tripId),
      userId: const Value('u1'),
      role: const Value('owner'),
      status: const Value('active'),
      displayName: const Value('Tiziano'),
    ),
  );
}

Future<void> _expense(
  AppDatabase db, {
  required String id,
  required String tripId,
  required String description,
  required int amountCents,
  required DateTime at,
  String payerId = 'u1',
  String createdBy = 'u1',
}) {
  return db.upsertExpense(
    LocalExpensesCompanion(
      id: Value(id),
      tripId: Value(tripId),
      description: Value(description),
      category: const Value('food'),
      amountCents: Value(amountCents),
      baseCents: Value(amountCents),
      currency: const Value('EUR'),
      payerId: Value(payerId),
      fxRate: const Value(1.0),
      spentAt: Value(at),
      createdBy: Value(createdBy),
      createdAt: Value(at),
    ),
  );
}
