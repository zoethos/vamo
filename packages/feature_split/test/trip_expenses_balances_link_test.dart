import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:feature_split/src/expenses/expense_consent_providers.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expenses_providers.dart';
import 'package:feature_split/src/expenses/trip_expenses_balances_link.dart';
import 'package:feature_split/src/trips/trip_budget_labels.dart';
import 'package:feature_split/src/trips/trip_expenses_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'governance_test_labels.dart';

const _tripId = 'trip-1';

void main() {
  group('TripExpensesBalancesLink widget', () {
    testWidgets('renders the quiet link and pushes the balances route', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(
            path: '/start',
            builder: (_, __) => const Scaffold(
              body: TripExpensesBalancesLink(
                tripId: _tripId,
                label: 'Balances',
                visible: true,
              ),
            ),
          ),
          GoRoute(
            path: '/trips/:tripId/balances',
            builder: (_, state) => Scaffold(
              body: Text('balances-${state.pathParameters['tripId']}'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('Balances'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(find.text('balances-$_tripId'), findsOneWidget);
    });

    testWidgets('renders nothing when not visible', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TripExpensesBalancesLink(
              tripId: _tripId,
              label: 'Balances',
              visible: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Balances'), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('TripExpensesTab balances-link gating', () {
    testWidgets('group trip (2+ members) shows the link', (tester) async {
      await _pumpTab(
        tester,
        membersStream: Stream.value(const [
          TripMemberView(userId: 'u1', displayName: 'Ann', role: 'owner'),
          TripMemberView(userId: 'u2', displayName: 'Ben', role: 'member'),
        ]),
      );

      expect(find.text('Balances'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('solo trip (1 member) hides the link', (tester) async {
      await _pumpTab(
        tester,
        membersStream: Stream.value(const [
          TripMemberView(userId: 'u1', displayName: 'Ann', role: 'owner'),
        ]),
      );

      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('hides the link while members are still loading', (
      tester,
    ) async {
      // A stream that never emits keeps the provider in its loading state.
      await _pumpTab(
        tester,
        membersStream: Stream.fromFuture(
          Completer<List<TripMemberView>>().future,
        ),
      );

      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });
  });
}

Future<void> _pumpTab(
  WidgetTester tester, {
  required Stream<List<TripMemberView>> membersStream,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => null),
        tripExpensesProvider(
          _tripId,
        ).overrideWith((ref) => Stream.value(const [])),
        tripExpenseSharesProvider(
          _tripId,
        ).overrideWith((ref) => Stream.value(const [])),
        tripMembersForExpenseProvider(
          _tripId,
        ).overrideWith((ref) => membersStream),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TripExpensesTab(
            tripId: _tripId,
            baseCurrency: 'EUR',
            readOnly: false,
            governanceLabels: governanceTestLabels,
            budgetLabels: _budgetLabels,
            balancesLabel: 'Balances',
          ),
        ),
      ),
    ),
  );
  // Deliver the expenses/members stream events (no pumpAndSettle — the
  // loading-case stream never closes).
  await tester.pump();
  await tester.pump();
}

const _budgetLabels = TripBudgetLabels(
  settingsTitle: 'Trip settings',
  budgetSectionTitle: 'Budget',
  budgetModeNone: 'No budget',
  budgetModeInformational: 'Informational',
  budgetModeFormal: 'Formal',
  budgetAmountLabel: 'Amount',
  saveBudget: 'Save budget',
  burnDownRemaining: _mockRemaining,
  burnDownOver: _mockOver,
  fxSectionTitle: 'Exchange rates',
  fxAddCurrency: 'Add currency',
  fxRefresh: 'Refresh',
  fxCapturedAt: _mockCapturedAt,
  fxSource: 'Source',
  fxRateReadOnly: 'Market rates only — not editable',
  overBudgetCommitTitle: 'Over budget',
  overBudgetCommitBody: 'Confirm to proceed',
  overBudgetConfirmHint: _mockHint,
  overBudgetConfirmPhrase: 'OVER BUDGET',
  confirm: 'Confirm',
  cancel: 'Cancel',
  currencyMissingAdmin: 'Ask admin',
  datesSectionTitle: 'Dates',
  startDateLabel: 'Start date',
  endDateLabel: 'End date',
  saveDates: 'Save dates',
  startDateLockedHint: 'Start date is locked',
  endBeforeStart: 'End date must be on or after start date.',
  datePickerCancel: 'Cancel',
  datePickerSkip: 'Skip',
  datePickerSelect: 'Select',
  retentionSectionTitle: 'Storage & retention',
  offloadMedia: 'Offload media',
  offloadMediaBody: 'Remove local copies.',
  offloadMediaConfirmTitle: 'Offload local media?',
  offloadMediaConfirmBody: 'Only backed-up media will be removed.',
  offloadMediaSuccess: _mockOffloadSuccess,
  offloadMediaNothing: 'No backed-up local media to offload.',
);

String _mockRemaining(int cents, String currency) => '$cents $currency left';
String _mockOver(String currency) => 'Over $currency';
String _mockCapturedAt(String iso) => 'Captured $iso';
String _mockHint(String phrase) => 'Type $phrase';
String _mockOffloadSuccess(int count) => '$count cached items offloaded.';
