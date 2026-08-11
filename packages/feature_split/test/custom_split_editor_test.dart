import 'package:feature_split/src/expenses/custom_split_editor.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const members = [
    TripMemberView(userId: 'a', displayName: 'Ana', role: 'owner'),
    TripMemberView(userId: 'b', displayName: 'Bea', role: 'member'),
  ];

  testWidgets('requires a complete custom allocation before saving', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomSplitEditor(
            members: members,
            baseCents: 1000,
            currency: 'EUR',
            initialShareCents: {'a': 500, 'b': 500},
          ),
        ),
      ),
    );

    expect(find.text('Split total matches the expense.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);

    await tester.enterText(
        find.byKey(const Key('customSplitAmount_a')), '7.00');
    await tester.pump();

    expect(find.textContaining('Over by'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });
}
