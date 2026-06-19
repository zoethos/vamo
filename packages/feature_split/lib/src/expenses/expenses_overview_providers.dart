import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settle/settle_up.dart';
import '../settle/settlements_repository.dart';
import '../trips/trips_models.dart';
import '../trips/trips_providers.dart';
import 'expense_governance.dart';
import 'expense_models.dart';
import 'expenses_overview.dart';

final expensesOverviewProvider = StreamProvider<ExpensesOverview>((ref) {
  final userId = ref.watch(currentUserProvider)?.id;
  return ref.watch(expensesOverviewRepositoryProvider).watch(userId: userId);
});

final expensesOverviewRepositoryProvider =
    Provider<ExpensesOverviewRepository>((ref) {
  return ExpensesOverviewRepository(
    db: ref.watch(appDatabaseProvider),
    settlements: ref.watch(settlementsRepositoryProvider),
  );
});

/// Drift-backed cross-trip aggregates for the Expenses overview tab.
class ExpensesOverviewRepository {
  ExpensesOverviewRepository({
    required AppDatabase db,
    required SettlementsRepository settlements,
  })  : _db = db,
        _settlements = settlements;

  final AppDatabase _db;
  final SettlementsRepository _settlements;

  Stream<ExpensesOverview> watch({required String? userId}) async* {
    final updates = StreamController<void>.broadcast();
    final subs = <StreamSubscription<dynamic>>[
      _db.watchAllTrips().listen((_) => updates.add(null)),
      _db.watchAllExpenses().listen((_) => updates.add(null)),
      _db.watchAllSettlements().listen((_) => updates.add(null)),
    ];

    try {
      yield await _build(userId: userId);
      await for (final _ in updates.stream) {
        yield await _build(userId: userId);
      }
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
      await updates.close();
    }
  }

  Future<ExpensesOverview> _build({required String? userId}) async {
    final now = DateTime.now();
    final tripRows = await _db.select(_db.localTrips).get();
    final trips = tripRows
        .map(
          (t) => TripSummary(
            id: t.id,
            name: t.name,
            destination: t.destination,
            startDate: t.startDate,
            endDate: t.endDate,
            baseCurrency: t.baseCurrency,
          ),
        )
        .toList();

    final expenseRows = await _db.select(_db.localExpenses).get();
    final expenses = expenseRows
        .map(
          (r) => ExpenseSummary(
            id: r.id,
            tripId: r.tripId,
            description: r.description,
            amountCents: r.amountCents,
            baseCents: r.baseCents,
            currency: r.currency,
            payerId: r.payerId,
            spentAt: r.spentAt,
            receiptPath: r.receiptPath,
            localReceiptPath: r.localReceiptPath,
            capturedLat: r.capturedLat,
            capturedLng: r.capturedLng,
            capturedAt: r.capturedAt,
            placeLabel: r.placeLabel,
            placeId: r.placeId,
            status: ExpenseStatus.parse(r.status),
            fxRateSource: r.fxRateSource,
            fxRateManual: r.fxRateManual,
            fxConversionLocked: r.fxConversionLocked,
          ),
        )
        .toList();

    final expenseIds = expenseRows.map((e) => e.id).toList();
    final shareRows = expenseIds.isEmpty
        ? <LocalExpenseShare>[]
        : await (_db.select(_db.localExpenseShares)
              ..where((s) => s.expenseId.isIn(expenseIds)))
            .get();

    final expenseTripById = {for (final e in expenseRows) e.id: e.tripId};
    final myShareByTrip = <String, int>{};
    if (userId != null) {
      for (final share in shareRows) {
        if (share.userId != userId) continue;
        final tripId = expenseTripById[share.expenseId];
        if (tripId == null) continue;
        myShareByTrip[tripId] =
            (myShareByTrip[tripId] ?? 0) + share.shareCents;
      }
    }

    final netsByTrip = <String, Map<String, int>>{};
    for (final trip in trips) {
      netsByTrip[trip.id] = await _netsForTrip(trip.id);
    }

    final tripCurrencyById = {for (final t in trips) t.id: t.baseCurrency};
    final rollups = buildTripRollups(
      trips: trips,
      expenses: expenses,
      netsByTripId: netsByTrip,
      myShareCentsByTripId: myShareByTrip,
      userId: userId,
      now: now,
    );

    return ExpensesOverview(
      rollups: rollups,
      balanceSummary: buildBalanceSummary(
        rollups: rollups,
        netsByTripId: netsByTrip,
        userId: userId,
      ),
      periodTotals: buildPeriodTotals(
        expenses: expenses,
        tripCurrencyById: tripCurrencyById,
        now: now,
      ),
      lastUsedTripId: lastUsedTripIdFromExpenses(expenses),
    );
  }

  Future<Map<String, int>> _netsForTrip(String tripId) async {
    final members = await (_db.select(_db.localTripMembers)
          ..where((m) => m.tripId.equals(tripId))
          ..where((m) => m.status.equals('active')))
        .get();

    final expenses = await (_db.select(_db.localExpenses)
          ..where((e) => e.tripId.equals(tripId)))
        .get();

    final expenseIds = expenses.map((e) => e.id).toList();
    final shares = expenseIds.isEmpty
        ? <LocalExpenseShare>[]
        : await (_db.select(_db.localExpenseShares)
              ..where((s) => s.expenseId.isIn(expenseIds)))
            .get();

    final settlementRows = await (_db.select(_db.localSettlements)
          ..where((s) => s.tripId.equals(tripId)))
        .get();
    final records = settlementRows.map(SettlementRecord.fromLocal);
    final totals = _settlements.settlementTotals(records);

    return computeNetBalances(
      activeMemberIds: members.map((m) => m.userId),
      expenses: expenses.map((e) => (payerId: e.payerId, baseCents: e.baseCents)),
      shares: shares.map((s) => (userId: s.userId, shareCents: s.shareCents)),
      settledOut: totals.out,
      settledIn: totals.in_,
    );
  }
}

/// Open trips for the add-expense FAB picker (recent non-closed first).
final expensePickerTripsProvider = Provider<List<TripSummary>>((ref) {
  final trips = ref.watch(tripsListProvider).valueOrNull ?? [];
  final overview = ref.watch(expensesOverviewProvider).valueOrNull;
  final now = DateTime.now();
  final open = openTripsForPicker(trips, now);
  final lastUsed = overview?.lastUsedTripId;
  if (lastUsed == null) return open;

  open.sort((a, b) {
    if (a.id == lastUsed) return -1;
    if (b.id == lastUsed) return 1;
    final rollupA = overview?.rollups.where((r) => r.tripId == a.id).firstOrNull;
    final rollupB = overview?.rollups.where((r) => r.tripId == b.id).firstOrNull;
    final keyA = rollupA?.sortKey ?? DateTime.utc(1970);
    final keyB = rollupB?.sortKey ?? DateTime.utc(1970);
    return keyB.compareTo(keyA);
  });
  return open;
});
