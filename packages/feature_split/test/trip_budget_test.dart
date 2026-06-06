import 'package:feature_split/src/trips/trip_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('burn-down counts committed expenses only', () {
    final burnDown = TripBudgetBurnDown.compute(
      mode: TripBudgetMode.formal,
      budgetCents: 10000,
      committedBaseCents: [3000, 2000],
    );
    expect(burnDown.committedSpendCents, 5000);
    expect(burnDown.remainingCents, 5000);
    expect(burnDown.isOverBudget, isFalse);
  });

  test('burn-down flags over budget when committed exceeds target', () {
    final burnDown = TripBudgetBurnDown.compute(
      mode: TripBudgetMode.formal,
      budgetCents: 4000,
      committedBaseCents: [3000, 2000],
    );
    expect(burnDown.isOverBudget, isTrue);
    expect(burnDown.remainingCents, -1000);
  });

  test('wouldExceedFormalBudget boundary is exclusive at exact budget', () {
    expect(
      wouldExceedFormalBudget(
        mode: TripBudgetMode.formal,
        budgetCents: 5000,
        committedSpendCents: 4000,
        additionalBaseCents: 1000,
      ),
      isFalse,
    );
    expect(
      wouldExceedFormalBudget(
        mode: TripBudgetMode.formal,
        budgetCents: 5000,
        committedSpendCents: 4000,
        additionalBaseCents: 1001,
      ),
      isTrue,
    );
  });

  test('informational mode never triggers formal over-budget flag', () {
    expect(
      wouldExceedFormalBudget(
        mode: TripBudgetMode.informational,
        budgetCents: 100,
        committedSpendCents: 5000,
        additionalBaseCents: 9999,
      ),
      isFalse,
    );
  });
}
