import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settle/settle_up.dart';
import '../settle/settlements_repository.dart';

final balancesRepositoryProvider = Provider<BalancesRepository>((ref) {
  return BalancesRepository(
    db: ref.watch(appDatabaseProvider),
    settlements: ref.watch(settlementsRepositoryProvider),
  );
});

/// Slice 3–4 — net balances from Drift (same formula as `trip_balances`).
class BalancesRepository {
  BalancesRepository({
    required AppDatabase db,
    required SettlementsRepository settlements,
  })  : _db = db,
        _settlements = settlements;

  final AppDatabase _db;
  final SettlementsRepository _settlements;

  Stream<({Map<String, int> nets, String currency})> watchTripBalances(
    String tripId,
  ) async* {
    final updates = StreamController<void>.broadcast();
    final subs = <StreamSubscription<dynamic>>[
      _db.watchTripExpenses(tripId).listen((_) => updates.add(null)),
      _db.watchTripSettlements(tripId).listen((_) => updates.add(null)),
    ];

    try {
      yield await _compute(tripId);
      await for (final _ in updates.stream) {
        yield await _compute(tripId);
      }
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
      await updates.close();
    }
  }

  Future<({Map<String, int> nets, String currency})> _compute(
    String tripId,
  ) async {
    final trip = await (_db.select(_db.localTrips)
          ..where((t) => t.id.equals(tripId)))
        .getSingleOrNull();
    final currency = trip?.baseCurrency ?? 'EUR';

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

    final nets = computeNetBalances(
      activeMemberIds: members.map((m) => m.userId),
      expenses: expenses.map((e) => (payerId: e.payerId, baseCents: e.baseCents)),
      shares: shares.map((s) => (userId: s.userId, shareCents: s.shareCents)),
      settledOut: totals.out,
      settledIn: totals.in_,
    );

    return (nets: nets, currency: currency);
  }

  List<SettlementLine> settleUpFromNets(Map<String, int> nets) => settleUp(nets);
}
