import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TripLifecycle', () {
    test('parse defaults unknown to active', () {
      expect(TripLifecycle.parse(null), TripLifecycle.active);
      expect(TripLifecycle.parse('nope'), TripLifecycle.active);
    });

    test('isTripReadOnly blocks closed states only', () {
      expect(isTripReadOnly(TripLifecycle.active), isFalse);
      expect(isTripReadOnly(TripLifecycle.closing), isFalse);
      expect(isTripReadOnly(TripLifecycle.closed), isTrue);
      expect(isTripReadOnly(TripLifecycle.unresolved), isTrue);
      expect(isTripReadOnly(TripLifecycle.cancelled), isTrue);
    });

    test('closeReviewDaysRemaining counts down 14-day window', () {
      final requested = DateTime.utc(2026, 1, 1);
      expect(
        closeReviewDaysRemaining(requested, DateTime.utc(2026, 1, 8)),
        7,
      );
      expect(
        closeReviewDaysRemaining(requested, DateTime.utc(2026, 1, 20)),
        0,
      );
    });
  });
}
