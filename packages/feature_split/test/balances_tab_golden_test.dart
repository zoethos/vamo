import 'package:app_core/app_core.dart';
import 'package:feature_split/src/balances/balances_models.dart';
import 'package:feature_split/src/balances/balances_providers.dart';
import 'package:feature_split/src/balances/balances_tab.dart';
import 'package:feature_split/src/expenses/expense_consent_providers.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expenses_providers.dart';
import 'package:feature_split/src/settle/settle_up.dart';
import 'package:feature_split/src/settle/settlements_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'golden_test_theme.dart';
import 'governance_test_labels.dart';
import 'trip_home_labels_test_support.dart';

void main() {
  const phone = Size(360, 740);

  testWidgets('balances net hero light small', (tester) async {
    await tester.binding.setSurfaceSize(phone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const tripId = 'trip-1';
    const you = 'user-you';
    const marco = 'user-marco';
    const lina = 'user-lina';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripNetBalancesProvider(tripId).overrideWith(
            (ref) => Stream.value((
              nets: {
                you: 38620,
                marco: -12050,
                lina: -8530,
              },
              currency: 'EUR',
            )),
          ),
          tripMembersForExpenseProvider(tripId).overrideWith(
            (ref) => Stream.value(const [
              TripMemberView(
                userId: you,
                displayName: 'You',
                role: 'owner',
              ),
              TripMemberView(
                userId: marco,
                displayName: 'Marco',
                role: 'member',
              ),
              TripMemberView(
                userId: lina,
                displayName: 'Lina',
                role: 'member',
              ),
            ]),
          ),
          tripSettleUpProvider(tripId).overrideWith(
            (ref) => AsyncValue.data([
              SettlementDisplay(
                line: SettlementLine(
                  fromUserId: marco,
                  toUserId: you,
                  cents: 12050,
                ),
                fromName: 'Marco',
                toName: 'You',
                currency: 'EUR',
              ),
              SettlementDisplay(
                line: SettlementLine(
                  fromUserId: lina,
                  toUserId: you,
                  cents: 8530,
                ),
                fromName: 'Lina',
                toName: 'You',
                currency: 'EUR',
              ),
              SettlementDisplay(
                line: SettlementLine(
                  fromUserId: you,
                  toUserId: marco,
                  cents: 6420,
                ),
                fromName: 'You',
                toName: 'Alex',
                currency: 'EUR',
              ),
            ]),
          ),
          tripPendingConfirmationsProvider(tripId).overrideWith((ref) => []),
          tripPayerAwaitingConfirmProvider(tripId).overrideWith((ref) => []),
          tripShareConsentFlagsProvider(tripId).overrideWith((ref) => []),
          currentUserProvider.overrideWith(
            (ref) => User(
              id: you,
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: goldenTestTheme(),
          home: Scaffold(
            appBar: AppBar(title: const Text('Balances')),
            body: BalancesTab(
              tripId: tripId,
              governanceLabels: governanceTestLabels,
              labels: testBalancesTabLabels,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/balances_net_hero_light_small.png'),
    );
  });
}
