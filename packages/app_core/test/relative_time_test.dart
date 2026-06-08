import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 6, 7, 15);

  test('formatRelativeTime today yesterday and days ago', () {
    expect(
      formatRelativeTime(DateTime(2026, 6, 7, 9), now: now),
      'Today',
    );
    expect(
      formatRelativeTime(DateTime(2026, 6, 6, 9), now: now),
      'Yesterday',
    );
    expect(
      formatRelativeTime(DateTime(2026, 6, 4, 9), now: now),
      '3 days ago',
    );
  });
}
