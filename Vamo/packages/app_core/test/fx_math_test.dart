import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fxRateExpenseToBase', () {
    test('same currency is 1', () {
      expect(
        fxRateExpenseToBase(
          expenseCurrency: 'EUR',
          baseCurrency: 'EUR',
          unitsPerOneBase: const {'USD': 1.08},
        ),
        1.0,
      );
    });

    test('USD expense on EUR trip uses inverse of USD per EUR', () {
      // 1 EUR = 1.08 USD → 1 USD ≈ 0.926 EUR
      final rate = fxRateExpenseToBase(
        expenseCurrency: 'USD',
        baseCurrency: 'EUR',
        unitsPerOneBase: const {'USD': 1.08, 'EUR': 1.0},
      );
      expect(rate, closeTo(1 / 1.08, 1e-9));
    });
  });

  group('convertExpenseCentsToBase', () {
    test('\$100 on EUR trip at 1 USD = 0.93 EUR', () {
      expect(
        convertExpenseCentsToBase(amountCents: 10000, fxRate: 0.93),
        9300,
      );
    });
  });
}
