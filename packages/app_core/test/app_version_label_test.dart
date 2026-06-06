import 'package:app_core/src/suggestions/suggestions_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatAppVersionLabel keeps Android four-part tester version clean',
      () {
    expect(
      formatAppVersionLabel(version: '0.2.0.7', buildNumber: '7'),
      '0.2.0.7',
    );
  });

  test('formatAppVersionLabel preserves Flutter version plus build fallback',
      () {
    expect(
      formatAppVersionLabel(version: '0.2.0', buildNumber: '7'),
      '0.2.0+7',
    );
  });
}
