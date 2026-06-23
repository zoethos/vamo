import 'package:app_core/app_core.dart';
import 'package:feature_split/src/expenses/expense_consent_providers.dart';
import 'package:feature_split/src/expenses/expense_governance.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expenses_providers.dart';
import 'package:feature_split/src/expenses/trip_expense_list_tile.dart';
import 'package:feature_split/src/expenses/trip_spend_summary.dart';
import 'package:feature_split/src/trips/trip_budget_labels.dart';
import 'package:feature_split/src/trips/trip_expenses_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'governance_test_labels.dart';

const _tripId = 'trip-1';
const _me = 'me';

void main() {
  group('shortMerchantName (§A)', () {
    test('takes the first segment and Title-Cases a shouting legal name', () {
      expect(
        shortMerchantName('BORRI BOOKS · SOC, TBRERIA TERMINI SRL'),
        'Borri Books',
      );
    });

    test('keeps non-shouting input verbatim', () {
      expect(shortMerchantName('Ferry tickets'), 'Ferry tickets');
      expect(shortMerchantName('Sfizio'), 'Sfizio');
    });

    test('caps at three words', () {
      expect(shortMerchantName('one two three four five'), 'one two three');
    });
  });

  group('tripSpendSummaryProvider (§B)', () {
    test('sums committed spend and the current user\'s share only', () {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith((ref) => _user(_me)),
          tripExpensesProvider(_tripId).overrideWith(
            (ref) => Stream.value([
              _expense(id: 'e1', baseCents: 4800),
              _expense(id: 'e2', baseCents: 120),
              // Proposed + cancelled must not count toward spend.
              _expense(id: 'e3', baseCents: 9999, status: ExpenseStatus.proposed),
              _expense(
                id: 'e4',
                baseCents: 5000,
                status: ExpenseStatus.cancelled,
              ),
            ]),
          ),
          tripExpenseSharesProvider(_tripId).overrideWith(
            (ref) => Stream.value([
              _share(expenseId: 'e1', userId: _me, shareCents: 2400),
              _share(expenseId: 'e2', userId: _me, shareCents: 60),
              _share(expenseId: 'e1', userId: 'other', shareCents: 2400),
              // Share on a non-committed expense is ignored.
              _share(expenseId: 'e3', userId: _me, shareCents: 9999),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Let the stream providers emit.
      container.read(tripExpensesProvider(_tripId));
      container.read(tripExpenseSharesProvider(_tripId));

      return Future<void>.delayed(Duration.zero, () {
        final summary = container.read(tripSpendSummaryProvider(_tripId));
        expect(summary.totalSpentCents, 4920);
        expect(summary.yourShareCents, 2460);
      });
    });
  });

  group('TripExpensesTab list (§C)', () {
    testWidgets('groups rows by day with a subtotal and shows the summary', (
      tester,
    ) async {
      await _pumpTab(
        tester,
        expenses: [
          _expense(
            id: 'e1',
            description: 'BORRI BOOKS · SRL',
            baseCents: 4800,
            spentAt: DateTime.utc(2026, 6, 5),
          ),
          _expense(
            id: 'e2',
            description: 'Sfizio',
            baseCents: 120,
            spentAt: DateTime.utc(2026, 6, 5),
          ),
          _expense(
            id: 'e3',
            description: 'Ferry tickets',
            baseCents: 3200,
            spentAt: DateTime.utc(2026, 6, 4),
          ),
        ],
      );

      // Summary header (the metric label renders uppercased).
      expect(
        find.text(governanceTestLabels.totalSpent.toUpperCase()),
        findsOneWidget,
      );
      expect(find.textContaining('81.20'), findsOneWidget); // 48 + 1.20 + 32
      // Two day-group headers.
      expect(find.text('JUN 5'), findsOneWidget);
      expect(find.text('JUN 4'), findsOneWidget);
      // Short titles, not the full legal name.
      expect(find.text('Borri Books'), findsOneWidget);
      expect(find.text('Ferry tickets'), findsOneWidget);
    });

    testWidgets('the Mine filter keeps only the current user\'s expenses', (
      tester,
    ) async {
      await _pumpTab(
        tester,
        currentUserId: _me,
        expenses: [
          _expense(id: 'e1', description: 'Mine pays', payerId: _me),
          _expense(id: 'e2', description: 'Theirs', payerId: 'other'),
        ],
        shares: [_share(expenseId: 'e1', userId: _me, shareCents: 100)],
      );

      expect(find.text('Mine pays'), findsOneWidget);
      expect(find.text('Theirs'), findsOneWidget);

      await tester.tap(find.text(governanceTestLabels.filterMine));
      await tester.pumpAndSettle();

      expect(find.text('Mine pays'), findsOneWidget);
      expect(find.text('Theirs'), findsNothing);
    });
  });
}

Future<void> _pumpTab(
  WidgetTester tester, {
  required List<ExpenseSummary> expenses,
  List<ExpenseShareSummary> shares = const [],
  List<TripMemberView> members = const [
    TripMemberView(userId: _me, displayName: 'Me', role: 'owner'),
    TripMemberView(userId: 'other', displayName: 'Other', role: 'member'),
  ],
  String? currentUserId,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => currentUserId == null ? null : _user(currentUserId),
        ),
        tripExpensesProvider(_tripId).overrideWith((ref) => Stream.value(expenses)),
        tripExpenseSharesProvider(_tripId)
            .overrideWith((ref) => Stream.value(shares)),
        tripMembersForExpenseProvider(_tripId)
            .overrideWith((ref) => Stream.value(members)),
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
  await tester.pump();
  await tester.pump();
}

ExpenseSummary _expense({
  required String id,
  int baseCents = 1000,
  String description = 'Expense',
  String payerId = _me,
  ExpenseStatus status = ExpenseStatus.committed,
  DateTime? spentAt,
}) =>
    ExpenseSummary(
      id: id,
      tripId: _tripId,
      description: description,
      amountCents: baseCents,
      baseCents: baseCents,
      currency: 'EUR',
      payerId: payerId,
      spentAt: spentAt ?? DateTime.utc(2026, 6, 5),
      status: status,
    );

ExpenseShareSummary _share({
  required String expenseId,
  required String userId,
  required int shareCents,
}) =>
    ExpenseShareSummary(
      id: '$expenseId-$userId',
      expenseId: expenseId,
      userId: userId,
      shareCents: shareCents,
      response: ShareResponse.accepted,
    );

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    );

const _budgetLabels = TripBudgetLabels(
  settingsTitle: 'Trip settings',
  budgetSectionTitle: 'Budget',
  budgetModeNone: 'No budget',
  budgetModeInformational: 'Informational',
  budgetModeFormal: 'Formal',
  budgetAmountLabel: 'Amount',
  saveBudget: 'Save budget',
  burnDownRemaining: _remaining,
  burnDownOver: _over,
  fxSectionTitle: 'Exchange rates',
  fxAddCurrency: 'Add currency',
  fxRefresh: 'Refresh',
  fxCapturedAt: _capturedAt,
  fxSource: 'Source',
  fxRateReadOnly: 'Market rates only',
  overBudgetCommitTitle: 'Over budget',
  overBudgetCommitBody: 'Confirm to proceed',
  overBudgetConfirmHint: _hint,
  overBudgetConfirmPhrase: 'OVER BUDGET',
  confirm: 'Confirm',
  cancel: 'Cancel',
  currencyMissingAdmin: 'Ask admin',
  datesSectionTitle: 'Dates',
  startDateLabel: 'Start date',
  endDateLabel: 'End date',
  saveDates: 'Save dates',
  startDateLockedHint: 'Locked',
  endBeforeStart: 'End before start',
  datePickerCancel: 'Cancel',
  datePickerSkip: 'Skip',
  datePickerSelect: 'Select',
  retentionSectionTitle: 'Storage',
  offloadMedia: 'Offload media',
  offloadMediaBody: 'Remove local copies.',
  offloadMediaConfirmTitle: 'Offload?',
  offloadMediaConfirmBody: 'Backed-up only.',
  offloadMediaSuccess: _offloadSuccess,
  offloadMediaNothing: 'Nothing to offload.',
);

String _remaining(int cents, String currency) => '$cents $currency left';
String _over(String currency) => 'Over $currency';
String _capturedAt(String iso) => 'Captured $iso';
String _hint(String phrase) => 'Type $phrase';
String _offloadSuccess(int count) => '$count offloaded.';
