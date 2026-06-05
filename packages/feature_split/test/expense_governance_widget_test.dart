import 'package:app_core/app_core.dart';
import 'package:feature_split/src/expenses/expense_governance.dart';
import 'package:feature_split/src/expenses/trip_expense_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('proposed expense tile uses ghost styling', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TripExpenseListTile(
            description: 'Hotel deposit',
            payer: 'Alex',
            spentAt: DateTime.utc(2026, 7, 1),
            baseCents: 5000,
            amountCents: 5000,
            tripBaseCurrency: 'EUR',
            expenseCurrency: 'EUR',
            status: ExpenseStatus.proposed,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Proposal'), findsOneWidget);
  });

  testWidgets('disputed label renders on expense row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TripExpenseListTile(
            description: 'Dinner',
            payer: 'Alex',
            spentAt: DateTime.utc(2026, 7, 1),
            baseCents: 3000,
            amountCents: 3000,
            tripBaseCurrency: 'EUR',
            expenseCurrency: 'EUR',
            consentLabel: 'included — disputed by Marco',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('disputed by Marco'), findsOneWidget);
  });
}
