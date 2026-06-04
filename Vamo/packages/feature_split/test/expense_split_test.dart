import 'package:feature_split/feature_split.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('equalSplit', () {
    test('€30 split 3 ways is 1000 cents each', () {
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

    test('remainder cents go to first sorted members', () {
      final shares = equalSplit(
        baseCents: 3001,
        memberIds: ['c', 'a', 'b'],
      );
      expect(shares[0].userId, 'a');
      expect(shares[0].shareCents, 1001);
      expect(shares[1].shareCents, 1000);
      expect(shares[2].shareCents, 1000);
    });

    test('solo member gets the full amount', () {
      final shares = equalSplit(
        baseCents: 4500,
        memberIds: ['solo'],
      );
      expect(shares.single.shareCents, 4500);
    });
  });

  group('assertSharesSumToBase', () {
    test('throws when sum diverges', () {
      expect(
        () => assertSharesSumToBase(baseCents: 100, shareCents: [40, 40]),
        throwsStateError,
      );
    });
  });
}
