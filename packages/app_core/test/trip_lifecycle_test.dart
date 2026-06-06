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

  group('resolveTripPhase', () {
    test('pre-start when active and start date is in the future', () {
      expect(
        resolveTripPhase(
          lifecycle: TripLifecycle.active,
          startDateIso: '2026-12-01',
          now: DateTime.utc(2026, 6, 5),
        ),
        TripPhase.preStart,
      );
    });

    test('ongoing when active and start date is today or past', () {
      expect(
        resolveTripPhase(
          lifecycle: TripLifecycle.active,
          startDateIso: '2026-06-05',
          now: DateTime.utc(2026, 6, 5, 12),
        ),
        TripPhase.ongoing,
      );
      expect(
        resolveTripPhase(
          lifecycle: TripLifecycle.active,
          startDateIso: null,
          now: DateTime.utc(2026, 6, 5),
        ),
        TripPhase.ongoing,
      );
    });

    test('closing and read-only follow lifecycle', () {
      expect(
        resolveTripPhase(
          lifecycle: TripLifecycle.closing,
          startDateIso: '2026-12-01',
          now: DateTime.utc(2026, 6, 5),
        ),
        TripPhase.closing,
      );
      expect(
        resolveTripPhase(
          lifecycle: TripLifecycle.closed,
          startDateIso: null,
          now: DateTime.utc(2026, 6, 5),
        ),
        TripPhase.readOnly,
      );
    });
  });
}
