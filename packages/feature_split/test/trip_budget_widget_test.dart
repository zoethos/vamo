import 'package:app_core/app_core.dart';
import 'package:feature_split/src/expenses/expense_consent_providers.dart';
import 'package:feature_split/src/trips/over_budget_confirm_dialog.dart';
import 'package:feature_split/src/trips/trip_budget.dart';
import 'package:feature_split/src/trips/trip_budget_labels.dart';
import 'package:feature_split/src/trips/trip_fx_models.dart';
import 'package:feature_split/src/trips/trip_settings_screen.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:feature_split/src/trips/trips_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _testBudgetLabels = TripBudgetLabels(
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
);

String _mockRemaining(int cents, String currency) => '$cents $currency left';
String _mockOver(String currency) => 'Over $currency';
String _mockCapturedAt(String iso) => 'Captured $iso';
String _mockHint(String phrase) => 'Type $phrase';

void main() {
  testWidgets('formal over-budget confirm requires exact phrase',
      (tester) async {
    var confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                confirmed = await confirmFormalOverBudgetCommit(
                  context: context,
                  labels: _testBudgetLabels,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('OVER BUDGET'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'OVER BUDGET');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(confirmed, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('FX rate field is not editable in settings copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Text(_testBudgetLabels.fxRateReadOnly),
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('Market rates only — not editable'),
      findsOneWidget,
    );
  });

  test('canManageTripBudgetAndFx hides writes for members', () {
    expect(
      canManageTripBudgetAndFx(tripReadOnly: false, memberRole: 'member'),
      isFalse,
    );
    expect(
      canManageTripBudgetAndFx(tripReadOnly: false, memberRole: 'co-admin'),
      isTrue,
    );
    expect(
      canManageTripBudgetAndFx(tripReadOnly: true, memberRole: 'owner'),
      isFalse,
    );
  });

  testWidgets('TripSettingsScreen hides budget and FX writes for members', (
    tester,
  ) async {
    const tripId = 'trip-budget-test';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith(
            (ref) => User(
              id: 'member-1',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
            ),
          ),
          currentMemberRoleProvider.overrideWith(
            (ref, args) => 'member',
          ),
          tripDetailProvider(tripId).overrideWith(
            (ref) => Stream.value(
              const TripDetail(
                id: tripId,
                name: 'Budget trip',
                baseCurrency: 'EUR',
                ownerId: 'owner',
                lifecycle: 'active',
                budgetMode: 'formal',
                budgetCents: 50000,
              ),
            ),
          ),
          tripFxRatesProvider(tripId).overrideWith(
            (ref) => Stream.value([
              TripFxRateRow(
                id: 'rate-1',
                tripId: tripId,
                currency: 'USD',
                rate: 0.93,
                source: 'exchangerate.host',
                capturedAt: DateTime.utc(2026, 6, 1),
                capturedBy: 'owner',
              ),
            ]),
          ),
          tripBudgetBurnDownProvider(tripId).overrideWith(
            (ref) => TripBudgetBurnDown.compute(
              mode: TripBudgetMode.formal,
              budgetCents: 50000,
              committedBaseCents: const [12000],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const TripSettingsScreen(
            tripId: tripId,
            labels: _testBudgetLabels,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_testBudgetLabels.saveBudget), findsNothing);
    expect(find.text(_testBudgetLabels.fxAddCurrency), findsNothing);
    expect(find.text(_testBudgetLabels.fxRefresh), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('0.9300'), findsOneWidget);
    expect(find.text(_testBudgetLabels.fxRateReadOnly), findsOneWidget);

    // Member is not the owner → no editable Dates section.
    expect(find.text(_testBudgetLabels.datesSectionTitle), findsNothing);
  });

  testWidgets('owner not-started trip shows editable start and end dates', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      const TripDetail(
        id: 'trip-dates-future',
        name: 'Future trip',
        baseCurrency: 'EUR',
        ownerId: 'owner-1',
        lifecycle: 'active',
        startDate: '2099-12-01',
        endDate: '2099-12-10',
      ),
    );

    expect(find.text(_testBudgetLabels.datesSectionTitle), findsOneWidget);
    expect(find.text(_testBudgetLabels.saveDates), findsOneWidget);
    expect(find.text(_testBudgetLabels.startDateLockedHint), findsNothing);
  });

  testWidgets('owner started trip locks start date, keeps end editable', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      const TripDetail(
        id: 'trip-dates-past',
        name: 'Ongoing trip',
        baseCurrency: 'EUR',
        ownerId: 'owner-1',
        lifecycle: 'active',
        startDate: '2000-01-01',
        endDate: '2000-01-10',
      ),
    );

    expect(find.text(_testBudgetLabels.datesSectionTitle), findsOneWidget);
    expect(find.text(_testBudgetLabels.saveDates), findsOneWidget);
    expect(find.text(_testBudgetLabels.startDateLockedHint), findsOneWidget);
  });

  testWidgets('closing trip hides the editable Dates section', (tester) async {
    await _pumpSettings(
      tester,
      const TripDetail(
        id: 'trip-dates-closing',
        name: 'Closing trip',
        baseCurrency: 'EUR',
        ownerId: 'owner-1',
        lifecycle: 'closing',
        startDate: '2099-12-01',
      ),
    );

    expect(find.text(_testBudgetLabels.datesSectionTitle), findsNothing);
  });
}

Future<void> _pumpSettings(WidgetTester tester, TripDetail detail) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => User(
            id: 'owner-1',
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
          ),
        ),
        currentMemberRoleProvider.overrideWith((ref, args) => 'owner'),
        tripDetailProvider(detail.id).overrideWith(
          (ref) => Stream.value(detail),
        ),
        tripFxRatesProvider(detail.id).overrideWith((ref) => Stream.value([])),
        tripBudgetBurnDownProvider(detail.id).overrideWith((ref) => null),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: TripSettingsScreen(
          tripId: detail.id,
          labels: _testBudgetLabels,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
