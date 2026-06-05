import 'package:feature_split/src/expenses/expenses_overview.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feature_split/src/expenses/expense_governance.dart';
import 'package:feature_split/src/expenses/expense_models.dart';

void main() {
  final now = DateTime(2026, 6, 5);

  TripSummary trip({
    required String id,
    required String name,
    String? start,
    String? end,
  }) =>
      TripSummary(
        id: id,
        name: name,
        startDate: start,
        endDate: end,
        baseCurrency: 'EUR',
      );

  group('buildTripRollups', () {
    test('aggregates totals, my share, and unsettled flag', () {
      final trips = [
        trip(id: 't1', name: 'Rome', start: '2026-05-01', end: '2026-05-10'),
        trip(id: 't2', name: 'Paris', start: '2026-07-01', end: '2026-07-10'),
      ];
      final expenses = [
        ExpenseSummary(
          id: 'e1',
          tripId: 't1',
          description: 'Dinner',
          amountCents: 6000,
          baseCents: 6000,
          currency: 'EUR',
          payerId: 'u2',
          spentAt: DateTime.utc(2026, 5, 3),
          status: ExpenseStatus.committed,
        ),
        ExpenseSummary(
          id: 'e2',
          tripId: 't1',
          description: 'Taxi',
          amountCents: 2000,
          baseCents: 2000,
          currency: 'EUR',
          payerId: 'u1',
          spentAt: DateTime.utc(2026, 5, 4),
          status: ExpenseStatus.committed,
        ),
      ];

      final rollups = buildTripRollups(
        trips: trips,
        expenses: expenses,
        netsByTripId: {
          't1': {'u1': -2000, 'u2': 2000},
          't2': {'u1': 0, 'u2': 0},
        },
        myShareCentsByTripId: {'t1': 4000, 't2': 0},
        userId: 'u1',
        now: now,
      );

      final rome = rollups.firstWhere((r) => r.tripId == 't1');
      expect(rome.totalSpentCents, 8000);
      expect(rome.myShareCents, 4000);
      expect(rome.settlementState, TripRollupSettlementState.unsettled);
      expect(rome.myNetCents, -2000);

      final paris = rollups.firstWhere((r) => r.tripId == 't2');
      expect(paris.totalSpentCents, 0);
      expect(paris.settlementState, TripRollupSettlementState.allSettled);
    });

    test('sorts recent-first with upcoming before past', () {
      final trips = [
        trip(id: 'past', name: 'Past', start: '2025-01-01', end: '2025-01-05'),
        trip(id: 'soon', name: 'Soon', start: '2026-07-01', end: '2026-07-05'),
      ];

      final rollups = buildTripRollups(
        trips: trips,
        expenses: const [],
        netsByTripId: const {},
        myShareCentsByTripId: const {},
        userId: 'u1',
        now: now,
      );

      expect(rollups.first.tripId, 'soon');
      expect(rollups.last.isPast, isTrue);
    });
  });

  group('partitionRollupsByRecency', () {
    test('groups past trips by year under Earlier', () {
      final rollups = [
        TripExpenseRollup(
          tripId: 'a',
          tripName: '2024 trip',
          dateRange: null,
          totalSpentCents: 0,
          myShareCents: 0,
          currency: 'EUR',
          settlementState: TripRollupSettlementState.allSettled,
          myNetCents: 0,
          sortKey: DateTime.utc(2024, 6, 1),
          isPast: true,
          yearGroup: 2024,
        ),
        TripExpenseRollup(
          tripId: 'b',
          tripName: '2025 trip',
          dateRange: null,
          totalSpentCents: 0,
          myShareCents: 0,
          currency: 'EUR',
          settlementState: TripRollupSettlementState.allSettled,
          myNetCents: 0,
          sortKey: DateTime.utc(2025, 3, 1),
          isPast: true,
          yearGroup: 2025,
        ),
        TripExpenseRollup(
          tripId: 'c',
          tripName: 'Active',
          dateRange: null,
          totalSpentCents: 0,
          myShareCents: 0,
          currency: 'EUR',
          settlementState: TripRollupSettlementState.allSettled,
          myNetCents: 0,
          sortKey: DateTime.utc(2026, 6, 1),
          isPast: false,
          yearGroup: null,
        ),
      ];

      final partitioned = partitionRollupsByRecency(rollups);
      expect(partitioned.recent.map((r) => r.tripId), ['c']);
      expect(partitioned.earlierByYear.keys, {2024, 2025});
      expect(partitioned.earlierByYear[2024]!.single.tripId, 'a');
    });
  });

  group('buildBalanceSummary', () {
    test('sums owe and owed across non-settled trips', () {
      final rollups = [
        TripExpenseRollup(
          tripId: 't1',
          tripName: 'Rome',
          dateRange: null,
          totalSpentCents: 0,
          myShareCents: 0,
          currency: 'EUR',
          settlementState: TripRollupSettlementState.unsettled,
          myNetCents: -1500,
          sortKey: DateTime.utc(2026, 5, 1),
          isPast: false,
          yearGroup: null,
        ),
        TripExpenseRollup(
          tripId: 't2',
          tripName: 'Paris',
          dateRange: null,
          totalSpentCents: 0,
          myShareCents: 0,
          currency: 'EUR',
          settlementState: TripRollupSettlementState.unsettled,
          myNetCents: 500,
          sortKey: DateTime.utc(2026, 6, 1),
          isPast: false,
          yearGroup: null,
        ),
      ];

      final summary = buildBalanceSummary(
        rollups: rollups,
        netsByTripId: {
          't1': {'u1': -1500, 'u2': 1500},
          't2': {'u1': 500, 'u2': -500},
        },
        userId: 'u1',
      );

      expect(summary.oweTripCount, 1);
      expect(summary.oweCentsByCurrency['EUR'], 1500);
      expect(summary.owedCentsByCurrency['EUR'], 500);
      expect(summary.perTripRows, hasLength(2));
      expect(summary.allSettled, isFalse);
    });
  });
}
