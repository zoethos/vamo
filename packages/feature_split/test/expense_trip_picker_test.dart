import 'package:app_core/app_core.dart';
import 'package:feature_split/feature_split.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('trip picker highlights last-used and navigates on tap', (
    tester,
  ) async {
    final trips = [
      const TripSummary(
        id: 't-old',
        name: 'Old Trip',
        startDate: '2026-01-01',
        endDate: '2026-01-10',
        baseCurrency: 'EUR',
      ),
      const TripSummary(
        id: 't-recent',
        name: 'Recent Trip',
        startDate: '2026-06-01',
        endDate: '2026-06-20',
        baseCurrency: 'EUR',
      ),
    ];

    final overview = ExpensesOverview(
      rollups: const [],
      balanceSummary: const CrossTripBalanceSummary(
        oweCentsByCurrency: {},
        owedCentsByCurrency: {},
        oweTripCount: 0,
        perTripRows: [],
        allSettled: true,
      ),
      periodTotals: const PeriodTotals(
        monthByCurrency: {},
        yearByCurrency: {},
      ),
      lastUsedTripId: 't-recent',
    );

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => const Scaffold(
            body: _OpenPickerButton(),
          ),
        ),
        GoRoute(
          path: '/trips/:tripId/expenses/new',
          name: 'add_expense',
          builder: (_, state) => Scaffold(
            body: Text('add ${state.pathParameters['tripId']}'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expensePickerTripsProvider.overrideWithValue(trips),
          expensesOverviewProvider.overrideWith(
            (ref) => Stream.value(overview),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Recent Trip'), findsOneWidget);
    expect(find.textContaining('Last used'), findsOneWidget);

    await tester.tap(find.text('Recent Trip'));
    await tester.pumpAndSettle();

    expect(find.text('add t-recent'), findsOneWidget);
  });

  testWidgets('openAddExpenseFromShell skips picker for single open trip', (
    tester,
  ) async {
    final trips = [
      const TripSummary(
        id: 'only',
        name: 'Only Trip',
        baseCurrency: 'EUR',
      ),
    ];

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => const Scaffold(
            body: _DirectAddButton(),
          ),
        ),
        GoRoute(
          path: '/trips/:tripId/expenses/new',
          builder: (_, state) => Scaffold(
            body: Text('direct ${state.pathParameters['tripId']}'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expensePickerTripsProvider.overrideWithValue(trips),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );

    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    expect(find.text('direct only'), findsOneWidget);
    expect(find.text('Pick'), findsNothing);
  });
}

class _OpenPickerButton extends ConsumerWidget {
  const _OpenPickerButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => showExpenseTripPickerSheet(
        context: context,
        ref: ref,
        title: 'Pick trip',
        lastUsedLabel: 'Last used',
      ),
      child: const Text('open'),
    );
  }
}

class _DirectAddButton extends ConsumerWidget {
  const _DirectAddButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => openAddExpenseFromShell(
        context: context,
        ref: ref,
        pickerTitle: 'Pick',
        lastUsedLabel: 'Last used',
      ),
      child: const Text('add'),
    );
  }
}
