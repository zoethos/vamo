import 'package:app_core/app_core.dart';
import 'package:feature_split/feature_split.dart';
import 'package:flutter_test/flutter_test.dart';

/// Characterization tests for Wave-1 money math (S50 baseline).
///
/// Entry-time FX snapshot: `base_cents = round(amount_cents * fx_rate)` where
/// `fx_rate` is trip-base units per 1 unit of expense currency (stored on the
/// expense row at propose/commit time). Split remainder cents go to the first
/// members in sorted user-id order. Settle-up matches largest-first with
/// userId tie-break.
void main() {
  group('FX conversion — entry-time snapshot', () {
    test('same currency: fxRate 1.0, baseCents equals amountCents', () {
      expect(
        convertExpenseCentsToBase(amountCents: 5000, fxRate: 1.0),
        5000,
      );
    });

    test('USD on EUR trip via stored trip_fx_rates rate (base per 1 USD)', () {
      const amountUsdCents = 10000;
      const storedRate = 1.0 / 1.08;
      expect(
        convertExpenseCentsToBase(
          amountCents: amountUsdCents,
          fxRate: storedRate,
        ),
        9259,
      );
    });

    test('fxRateExpenseToBase inverts unitsPerOneBase table', () {
      const unitsPerEur = {'USD': 1.08, 'EUR': 1.0};
      final fxRate = fxRateExpenseToBase(
        expenseCurrency: 'USD',
        baseCurrency: 'EUR',
        unitsPerOneBase: unitsPerEur,
      );
      expect(fxRate, closeTo(1 / 1.08, 1e-12));
      expect(
        convertExpenseCentsToBase(amountCents: 10000, fxRate: fxRate),
        9259,
      );
    });

    test('rounding uses standard double round to integer cents', () {
      expect(
        convertExpenseCentsToBase(amountCents: 333, fxRate: 1 / 1.08),
        308,
      );
      expect(
        convertExpenseCentsToBase(amountCents: 1, fxRate: 0.9259259259259259),
        1,
      );
    });

    test('GBP on USD trip with captured rate', () {
      const rateGbpToUsd = 1.27;
      expect(
        convertExpenseCentsToBase(amountCents: 5000, fxRate: rateGbpToUsd),
        6350,
      );
    });
  });

  group('equalSplit — remainder to first sorted members', () {
    test('€30.00 split 3 ways yields exact 1000¢ shares', () {
      final shares = equalSplit(
        baseCents: 3000,
        memberIds: ['a', 'b', 'c'],
      );
      expect(shares.map((s) => s.shareCents).toList(), [1000, 1000, 1000]);
      assertSharesSumToBase(
        baseCents: 3000,
        shareCents: shares.map((s) => s.shareCents),
      );
    });

    test('3001¢ split 3 ways: +1¢ to first sorted id', () {
      final shares = equalSplit(
        baseCents: 3001,
        memberIds: ['c', 'a', 'b'],
      );
      expect(shares.map((s) => s.userId).toList(), ['a', 'b', 'c']);
      expect(shares.map((s) => s.shareCents).toList(), [1001, 1000, 1000]);
      assertSharesSumToBase(
        baseCents: 3001,
        shareCents: shares.map((s) => s.shareCents),
      );
    });

    test('7¢ split 3 ways distributes 3 remainder cents', () {
      final shares = equalSplit(
        baseCents: 7,
        memberIds: ['z', 'a', 'm'],
      );
      expect(shares.map((s) => s.userId).toList(), ['a', 'm', 'z']);
      expect(shares.map((s) => s.shareCents).toList(), [3, 2, 2]);
      assertSharesSumToBase(
        baseCents: 7,
        shareCents: shares.map((s) => s.shareCents),
      );
    });
  });

  group('settleUp — debtor/creditor ordering', () {
    test('equal dinner: two debtors pay payer, 1000¢ each', () {
      final lines = settleUp({'a': 2000, 'b': -1000, 'c': -1000});
      expect(lines, hasLength(2));
      expect(lines.every((l) => l.toUserId == 'a' && l.cents == 1000), isTrue);
      expect(lines.map((l) => l.fromUserId).toList(), ['b', 'c']);
    });

    test('largest debtor first; equal debtors tie-break by userId', () {
      final lines = settleUp({'z': 2000, 'x': -1000, 'y': -1000});
      expect(lines.map((l) => l.fromUserId).toList(), ['x', 'y']);
      expect(lines.every((l) => l.toUserId == 'z'), isTrue);
    });

    test('all zero nets produce no settlement lines', () {
      expect(settleUp({'a': 0, 'b': 0, 'c': 0}), isEmpty);
    });
  });

  group('mixed-currency — pre-converted nets only', () {
    test('three-way net clears with two payments totaling creditor balance', () {
      final lines = settleUp({'a': 1000, 'b': -600, 'c': -400});
      expect(lines, hasLength(2));
      expect(lines.fold<int>(0, (sum, l) => sum + l.cents), 1000);
      expect(lines.every((l) => l.toUserId == 'a'), isTrue);
    });

    test('computeNetBalances then settleUp for FX-mixed committed expenses', () {
      // A paid €50 (5000¢ base), B paid $54 (5000¢ base after conversion).
      final nets = computeNetBalances(
        activeMemberIds: ['a', 'b', 'c'],
        expenses: [
          (payerId: 'a', baseCents: 5000),
          (payerId: 'b', baseCents: 5000),
        ],
        shares: [
          (userId: 'a', shareCents: 3334),
          (userId: 'b', shareCents: 3333),
          (userId: 'c', shareCents: 3333),
        ],
      );
      expect(nets['a'], 1666);
      expect(nets['b'], 1667);
      expect(nets['c'], -3333);

      final lines = settleUp(nets);
      expect(lines.fold<int>(0, (s, l) => s + l.cents), 3333);
      assertSharesSumToBase(
        baseCents: 3333,
        shareCents: lines.map((l) => l.cents),
      );
    });
  });
}
