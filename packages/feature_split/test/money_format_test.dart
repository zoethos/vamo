import 'package:feature_split/src/expenses/expense_display.dart';
import 'package:feature_split/src/expenses/money_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatMoneyFromCents', () {
    test('uses Hindi lakh grouping for large INR amounts', () {
      expect(
        formatMoneyFromCents(10000000, 'INR', locale: 'hi_IN'),
        contains('1,00,000'),
      );
    });

    test('bidi wrapper embeds LTR isolates', () {
      final wrapped = formatMoneyFromCentsBidi(3000, 'EUR');
      expect(wrapped.startsWith(ltrIsolateStart), isTrue);
      expect(wrapped.endsWith(ltrIsolateEnd), isTrue);
      expect(wrapped, contains('€'));
    });
  });

  group('formatExpenseSubtitle', () {
    test('keeps euro amount intact inside Arabic sentence', () {
      const sentence = 'دفع أحمد';
      final line = formatExpenseSubtitle(
        payer: sentence,
        when: '٢ يونيو',
        baseCents: 3000,
        tripBaseCurrency: 'EUR',
      );
      expect(line, contains(sentence));
      expect(line, contains('€'));
      expect(line, contains(ltrIsolateStart));
    });
  });
}
