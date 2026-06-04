import 'package:app_core/app_core.dart';
import 'package:feature_split/feature_split.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('USD expense on EUR trip converts then splits equally', () {
    const amountUsdCents = 10000; // $100
    const unitsPerEur = {'USD': 1.08, 'EUR': 1.0};
    final fxRate = fxRateExpenseToBase(
      expenseCurrency: 'USD',
      baseCurrency: 'EUR',
      unitsPerOneBase: unitsPerEur,
    );
    final baseCents = convertExpenseCentsToBase(
      amountCents: amountUsdCents,
      fxRate: fxRate,
    );

    final shares = equalSplit(
      baseCents: baseCents,
      memberIds: const ['a', 'b'],
    );
    assertSharesSumToBase(
      baseCents: baseCents,
      shareCents: shares.map((s) => s.shareCents),
    );
    expect(baseCents, closeTo(9259, 2)); // ~€92.59
  });
}
