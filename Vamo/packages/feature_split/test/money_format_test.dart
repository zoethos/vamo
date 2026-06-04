import 'package:feature_split/feature_split.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseAmountToCents handles euros with decimals', () {
    expect(parseAmountToCents('30'), 3000);
    expect(parseAmountToCents('30.50'), 3050);
    expect(parseAmountToCents('30,5'), 3050);
  });

  test('parseAmountToCents rejects invalid input', () {
    expect(parseAmountToCents(''), isNull);
    expect(parseAmountToCents('abc'), isNull);
    expect(parseAmountToCents('-1'), isNull);
  });
}
