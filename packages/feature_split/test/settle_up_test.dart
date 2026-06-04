import 'package:feature_split/feature_split.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('settleUp', () {
    test('equal split: €30 dinner among 3 yields two payments to payer', () {
      // A paid 3000¢, each owes 1000¢.
      final lines = settleUp({'a': 2000, 'b': -1000, 'c': -1000});
      expect(lines, hasLength(2));
      expect(lines.every((l) => l.toUserId == 'a' && l.cents == 1000), isTrue);
      expect(lines.map((l) => l.fromUserId).toSet(), {'b', 'c'});
    });

    test('custom split: one payment clears balances', () {
      final lines = settleUp({'a': 4000, 'b': -4000});
      expect(lines, hasLength(1));
      expect(lines.single.fromUserId, 'b');
      expect(lines.single.toUserId, 'a');
      expect(lines.single.cents, 4000);
    });

    test('multi-payer: nets in base currency, minimal transfers', () {
      // A paid 10000, B paid 5000; each owes 5000.
      final lines = settleUp({'a': 5000, 'b': 0, 'c': -5000});
      expect(lines, hasLength(1));
      expect(lines.single.fromUserId, 'c');
      expect(lines.single.toUserId, 'a');
      expect(lines.single.cents, 5000);
    });

    test('multi-currency: uses pre-converted net map only', () {
      final lines = settleUp({'a': 1000, 'b': -600, 'c': -400});
      expect(lines, hasLength(2));
      final total = lines.fold<int>(0, (s, l) => s + l.cents);
      expect(total, 1000);
    });

    test('3-person cycle compresses to two payments', () {
      final lines = settleUp({'a': 3000, 'b': -2000, 'c': -1000});
      expect(lines, hasLength(2));
      expect(lines.fold<int>(0, (s, l) => s + l.cents), 3000);
    });

    test('all zero nets produce no settlements', () {
      expect(settleUp({'a': 0, 'b': 0}), isEmpty);
    });

    test('tie-breaking by userId is stable', () {
      final a = settleUp({'x': -1000, 'y': -1000, 'z': 2000});
      final b = settleUp({'x': -1000, 'y': -1000, 'z': 2000});
      expect(a.map((l) => l.fromUserId).toList(), b.map((l) => l.fromUserId).toList());
      expect(a.first.fromUserId, 'x');
      expect(a.last.fromUserId, 'y');
    });
  });

  group('computeNetBalances', () {
    test('marked settlements adjust nets like trip_balances view', () {
      final nets = computeNetBalances(
        activeMemberIds: ['a', 'b'],
        expenses: [(payerId: 'a', baseCents: 4000)],
        shares: [
          (userId: 'a', shareCents: 2000),
          (userId: 'b', shareCents: 2000),
        ],
        settledOut: {'b': 2000},
        settledIn: {'a': 2000},
      );
      expect(nets['a'], 0);
      expect(nets['b'], 0);
      expect(settleUp(nets), isEmpty);
    });

    test('matches trip_balances formula for payers and shares', () {
      final nets = computeNetBalances(
        activeMemberIds: ['a', 'b', 'c'],
        expenses: [(payerId: 'a', baseCents: 3000)],
        shares: [
          (userId: 'a', shareCents: 1000),
          (userId: 'b', shareCents: 1000),
          (userId: 'c', shareCents: 1000),
        ],
      );
      expect(nets, {'a': 2000, 'b': -1000, 'c': -1000});
      expect(
        settleUp(nets).length,
        2,
        reason: 'fewest payments for the 3-person dinner',
      );
    });
  });
}
