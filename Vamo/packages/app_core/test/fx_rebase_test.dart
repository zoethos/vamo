import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final eurPivot = FxRatesSnapshot(
    baseCurrency: 'EUR',
    unitsPerOneBase: const {'EUR': 1.0, 'USD': 1.08, 'GBP': 0.86},
    fetchedAt: DateTime.utc(2026, 6, 1),
  );

  test('rebaseFxSnapshot converts EUR pivot to GBP trip base', () {
    final gbp = rebaseFxSnapshot(eurPivot, tripBase: 'GBP');
    expect(gbp.baseCurrency, 'GBP');
    expect(gbp.unitsPerOneBase['GBP'], 1.0);
    expect(gbp.unitsPerOneBase['USD'], closeTo(1.08 / 0.86, 1e-9));
  });

  test('rebaseFxSnapshot USD expense rate on GBP trip', () {
    final gbp = rebaseFxSnapshot(eurPivot, tripBase: 'GBP');
    final rate = gbp.rateExpenseToBase('USD');
    // 1 GBP = (1.08/0.86) USD → 1 USD = 0.86/1.08 GBP
    expect(rate, closeTo(0.86 / 1.08, 1e-9));
  });
}
