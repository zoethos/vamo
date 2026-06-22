import 'package:app_core/app_core.dart';
import 'package:feature_split/src/expenses/add_expense_screen.dart';
import 'package:feature_split/src/expenses/expense_governance.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expenses_providers.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:feature_split/src/trips/trips_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'add_expense_test_labels.dart';
import 'golden_test_theme.dart';
import 'governance_test_labels.dart';

void main() {
  const phone = Size(360, 740);

  testWidgets('add expense amount-first light small', (tester) async {
    await tester.binding.setSurfaceSize(phone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripDetailProvider('trip-1').overrideWith(
            (ref) => Stream.value(
              const TripDetail(
                id: 'trip-1',
                name: 'Amalfi Coast',
                baseCurrency: 'EUR',
                ownerId: 'you',
                lifecycle: 'active',
              ),
            ),
          ),
          tripMembersForExpenseProvider('trip-1').overrideWith(
            (ref) => Stream.value(const [
              TripMemberView(
                userId: 'you',
                displayName: 'You',
                role: 'owner',
              ),
              TripMemberView(
                userId: 'marco',
                displayName: 'Marco',
                role: 'member',
              ),
              TripMemberView(
                userId: 'lisa',
                displayName: 'Lisa',
                role: 'member',
              ),
              TripMemberView(
                userId: 'sam',
                displayName: 'Sam',
                role: 'member',
              ),
            ]),
          ),
          tripExpensesProvider('trip-1').overrideWith(
            (ref) => Stream.value([
              ExpenseSummary(
                id: 'exp-1',
                tripId: 'trip-1',
                description: 'Lunch',
                amountCents: 4200,
                baseCents: 4200,
                currency: 'EUR',
                payerId: 'you',
                spentAt: DateTime.utc(2026, 6, 4),
                status: ExpenseStatus.committed,
                category: 'food',
              ),
            ]),
          ),
          tripFxRatesProvider('trip-1').overrideWith((ref) => Stream.value([])),
          currentUserProvider.overrideWith(
            (ref) => User(
              id: 'you',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: goldenTestTheme(),
          home: AddExpenseScreen(
            tripId: 'trip-1',
            labels: governanceTestLabels,
            screenLabels: addExpenseTestScreenLabels,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final digit in ['6', '4', '.', '2', '0']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/add_expense_amount_first_light_small.png'),
    );
  });
}
