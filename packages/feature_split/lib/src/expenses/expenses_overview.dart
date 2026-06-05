import '../trips/trip_format.dart';
import '../trips/trips_models.dart';
import 'expense_models.dart';

/// Settlement badge for a trip rollup row.
enum TripRollupSettlementState { unsettled, settled, allSettled }

/// Per-trip aggregate for the Expenses overview tab.
class TripExpenseRollup {
  const TripExpenseRollup({
    required this.tripId,
    required this.tripName,
    required this.dateRange,
    required this.totalSpentCents,
    required this.myShareCents,
    required this.currency,
    required this.settlementState,
    required this.myNetCents,
    required this.sortKey,
    required this.isPast,
    required this.yearGroup,
  });

  final String tripId;
  final String tripName;
  final String? dateRange;
  final int totalSpentCents;
  final int myShareCents;
  final String currency;
  final TripRollupSettlementState settlementState;
  final int myNetCents;
  final DateTime sortKey;
  final bool isPast;
  final int? yearGroup;
}

/// Cross-trip balance header aggregates (non-settled trips only).
class CrossTripBalanceSummary {
  const CrossTripBalanceSummary({
    required this.oweCentsByCurrency,
    required this.owedCentsByCurrency,
    required this.oweTripCount,
    required this.perTripRows,
    required this.allSettled,
  });

  final Map<String, int> oweCentsByCurrency;
  final Map<String, int> owedCentsByCurrency;
  final int oweTripCount;
  final List<TripBalanceRow> perTripRows;
  final bool allSettled;
}

class TripBalanceRow {
  const TripBalanceRow({
    required this.tripId,
    required this.tripName,
    required this.netCents,
    required this.currency,
  });

  final String tripId;
  final String tripName;
  final int netCents;
  final String currency;
}

/// Month / year spend totals keyed by trip base currency.
class PeriodTotals {
  const PeriodTotals({
    required this.monthByCurrency,
    required this.yearByCurrency,
  });

  final Map<String, int> monthByCurrency;
  final Map<String, int> yearByCurrency;

  String? get primaryCurrency {
    if (yearByCurrency.isEmpty) return null;
    return yearByCurrency.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }
}

class ExpensesOverview {
  const ExpensesOverview({
    required this.rollups,
    required this.balanceSummary,
    required this.periodTotals,
    required this.lastUsedTripId,
  });

  final List<TripExpenseRollup> rollups;
  final CrossTripBalanceSummary balanceSummary;
  final PeriodTotals periodTotals;
  final String? lastUsedTripId;
}

/// Whether a trip has ended (same rule as Trips list “Past” filter).
bool isTripPast(TripSummary trip, DateTime now) {
  final end = parseTripDate(trip.endDate) ?? parseTripDate(trip.startDate);
  return end != null && end.isBefore(now);
}

TripRollupSettlementState settlementStateForTrip(
  Map<String, int> nets,
  String? userId,
) {
  if (nets.values.every((v) => v == 0)) {
    return TripRollupSettlementState.allSettled;
  }
  if (userId == null) return TripRollupSettlementState.allSettled;
  final net = nets[userId] ?? 0;
  if (net == 0) return TripRollupSettlementState.settled;
  return TripRollupSettlementState.unsettled;
}

bool isTripUnsettled(Map<String, int> nets) =>
    !nets.values.every((v) => v == 0);

DateTime rollupSortKey(TripSummary trip, List<ExpenseSummary> tripExpenses) {
  DateTime? latest;
  for (final e in tripExpenses) {
    if (latest == null || e.spentAt.isAfter(latest)) latest = e.spentAt;
  }
  final end = parseTripDate(trip.endDate);
  final start = parseTripDate(trip.startDate);
  final candidates = [latest, end, start].whereType<DateTime>();
  if (candidates.isEmpty) return DateTime.utc(1970);
  return candidates.reduce((a, b) => a.isAfter(b) ? a : b);
}

int? pastTripYear(TripSummary trip) {
  final d = parseTripDate(trip.endDate) ?? parseTripDate(trip.startDate);
  return d?.year;
}

List<TripExpenseRollup> buildTripRollups({
  required List<TripSummary> trips,
  required List<ExpenseSummary> expenses,
  required Map<String, Map<String, int>> netsByTripId,
  required Map<String, int> myShareCentsByTripId,
  required String? userId,
  required DateTime now,
}) {
  final expensesByTrip = <String, List<ExpenseSummary>>{};
  for (final e in expenses) {
    expensesByTrip.putIfAbsent(e.tripId, () => []).add(e);
  }

  final rollups = <TripExpenseRollup>[];
  for (final trip in trips) {
    final tripExpenses = expensesByTrip[trip.id] ?? const [];
    final nets = netsByTripId[trip.id] ?? const {};
    final totalSpent = tripExpenses.fold<int>(0, (s, e) => s + e.baseCents);
    final past = isTripPast(trip, now);
    rollups.add(
      TripExpenseRollup(
        tripId: trip.id,
        tripName: trip.name,
        dateRange: formatTripDateRange(trip.startDate, trip.endDate),
        totalSpentCents: totalSpent,
        myShareCents: myShareCentsByTripId[trip.id] ?? 0,
        currency: trip.baseCurrency,
        settlementState: settlementStateForTrip(nets, userId),
        myNetCents: userId == null ? 0 : (nets[userId] ?? 0),
        sortKey: rollupSortKey(trip, tripExpenses),
        isPast: past,
        yearGroup: past ? pastTripYear(trip) : null,
      ),
    );
  }

  rollups.sort((a, b) => b.sortKey.compareTo(a.sortKey));
  return rollups;
}

CrossTripBalanceSummary buildBalanceSummary({
  required List<TripExpenseRollup> rollups,
  required Map<String, Map<String, int>> netsByTripId,
  required String? userId,
}) {
  if (userId == null) {
    return const CrossTripBalanceSummary(
      oweCentsByCurrency: {},
      owedCentsByCurrency: {},
      oweTripCount: 0,
      perTripRows: [],
      allSettled: true,
    );
  }

  final oweByCurrency = <String, int>{};
  final owedByCurrency = <String, int>{};
  final rows = <TripBalanceRow>[];
  var oweTripCount = 0;

  for (final rollup in rollups) {
    final nets = netsByTripId[rollup.tripId] ?? const {};
    if (!isTripUnsettled(nets)) continue;

    final net = rollup.myNetCents;
    if (net < 0) {
      oweTripCount++;
      oweByCurrency[rollup.currency] =
          (oweByCurrency[rollup.currency] ?? 0) + net.abs();
    } else if (net > 0) {
      owedByCurrency[rollup.currency] =
          (owedByCurrency[rollup.currency] ?? 0) + net;
    }

    if (net != 0) {
      rows.add(
        TripBalanceRow(
          tripId: rollup.tripId,
          tripName: rollup.tripName,
          netCents: net,
          currency: rollup.currency,
        ),
      );
    }
  }

  rows.sort((a, b) => b.netCents.abs().compareTo(a.netCents.abs()));

  return CrossTripBalanceSummary(
    oweCentsByCurrency: oweByCurrency,
    owedCentsByCurrency: owedByCurrency,
    oweTripCount: oweTripCount,
    perTripRows: rows,
    allSettled: rollups.every(
      (r) =>
          settlementStateForTrip(netsByTripId[r.tripId] ?? const {}, userId) ==
          TripRollupSettlementState.allSettled,
    ),
  );
}

PeriodTotals buildPeriodTotals({
  required List<ExpenseSummary> expenses,
  required Map<String, String> tripCurrencyById,
  required DateTime now,
}) {
  final monthStart = DateTime(now.year, now.month);
  final yearStart = DateTime(now.year);
  final monthByCurrency = <String, int>{};
  final yearByCurrency = <String, int>{};

  for (final e in expenses) {
    final currency = tripCurrencyById[e.tripId] ?? e.currency;
    if (!e.spentAt.isBefore(monthStart)) {
      monthByCurrency[currency] =
          (monthByCurrency[currency] ?? 0) + e.baseCents;
    }
    if (!e.spentAt.isBefore(yearStart)) {
      yearByCurrency[currency] =
          (yearByCurrency[currency] ?? 0) + e.baseCents;
    }
  }

  return PeriodTotals(
    monthByCurrency: monthByCurrency,
    yearByCurrency: yearByCurrency,
  );
}

/// Splits rollups into recent (non-past) and past grouped by year (desc).
({List<TripExpenseRollup> recent, Map<int, List<TripExpenseRollup>> earlierByYear})
    partitionRollupsByRecency(List<TripExpenseRollup> rollups) {
  final recent = <TripExpenseRollup>[];
  final earlierByYear = <int, List<TripExpenseRollup>>{};

  for (final r in rollups) {
    if (!r.isPast) {
      recent.add(r);
    } else {
      final year = r.yearGroup;
      if (year != null) {
        earlierByYear.putIfAbsent(year, () => []).add(r);
      }
    }
  }

  for (final list in earlierByYear.values) {
    list.sort((a, b) => b.sortKey.compareTo(a.sortKey));
  }

  return (recent: recent, earlierByYear: earlierByYear);
}

String? lastUsedTripIdFromExpenses(List<ExpenseSummary> expenses) {
  if (expenses.isEmpty) return null;
  final sorted = List<ExpenseSummary>.from(expenses)
    ..sort((a, b) => b.spentAt.compareTo(a.spentAt));
  return sorted.first.tripId;
}

List<TripSummary> openTripsForPicker(
  List<TripSummary> trips,
  DateTime now,
) {
  final open = trips.where((t) => !isTripPast(t, now)).toList();
  if (open.isNotEmpty) return open;
  return List<TripSummary>.from(trips);
}
