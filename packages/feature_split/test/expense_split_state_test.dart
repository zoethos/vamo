import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expense_split.dart';
import 'package:feature_split/src/expenses/expense_split_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const members = [
    TripMemberView(userId: 'a', displayName: 'Ana', role: 'owner'),
    TripMemberView(userId: 'b', displayName: 'Bea', role: 'member'),
  ];

  test('custom split preserves explicit zero shares and the total', () {
    const state = ExpenseSplitState(
      mode: ExpenseSplitMode.custom,
      customShareCents: {'a': 1000, 'b': 0},
    );

    expect(state.validationMessage(baseCents: 1000, members: members), isNull);
    expect(
      state.resolve(baseCents: 1000, members: members),
      isA<List<ExpenseShareLine>>(),
    );
  });

  test('custom split rejects an amount that no longer matches the expense', () {
    const state = ExpenseSplitState(
      mode: ExpenseSplitMode.custom,
      customShareCents: {'a': 600, 'b': 300},
    );

    expect(
      state.validationMessage(baseCents: 1000, members: members),
      contains('sum(shares)=900'),
    );
  });

  test('custom split must include every active member exactly once', () {
    expect(
      () => validateCustomSplit(
        baseCents: 1000,
        memberIds: const ['a', 'b'],
        shares: const [ExpenseShareLine(userId: 'a', shareCents: 1000)],
      ),
      throwsArgumentError,
    );
  });
}
