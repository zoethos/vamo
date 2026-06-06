import 'package:app_core/app_core.dart';
import 'package:feature_split/src/expenses/trip_expense_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('place_label shows pin icon and graphite subtitle', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TripExpenseListTile(
              description: 'Lunch',
              payer: 'Alex',
              spentAt: DateTime(2026, 6, 2),
              baseCents: 1800,
              amountCents: 1800,
              tripBaseCurrency: 'EUR',
              expenseCurrency: 'EUR',
              placeLabel: 'Caffè Centrale',
              proposalRowPrefix: 'Proposal',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.place_outlined), findsOneWidget);
    expect(find.textContaining('Caffè Centrale'), findsOneWidget);
    final subtitle = tester.widget<Text>(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byWidgetPredicate(
          (w) => w is Text && (w.data?.contains('Caffè Centrale') ?? false),
        ),
      ),
    );
    expect(subtitle.style?.color, AppColors.graphite);
  });
}
