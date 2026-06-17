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

    test('closeReviewDaysRemainingFromNotice anchors on member notice', () {
      final notified = DateTime.utc(2026, 1, 1);
      expect(
        closeReviewDaysRemainingFromNotice(notified, DateTime.utc(2026, 1, 8)),
        7,
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

  group('tripDatesEditability', () {
    final now = DateTime.utc(2026, 6, 5, 12);

    test('not started (future start) allows both dates', () {
      final e = tripDatesEditability(
        lifecycle: TripLifecycle.active,
        startDateIso: '2026-12-01',
        now: now,
      );
      expect(e.canEditStart, isTrue);
      expect(e.canEditEnd, isTrue);
      expect(e.any, isTrue);
    });

    test('undated active trip counts as not started (both editable)', () {
      final e = tripDatesEditability(
        lifecycle: TripLifecycle.active,
        startDateIso: null,
        now: now,
      );
      expect(e.canEditStart, isTrue);
      expect(e.canEditEnd, isTrue);
    });

    test('started (start today or past) locks start, keeps end', () {
      final today = tripDatesEditability(
        lifecycle: TripLifecycle.active,
        startDateIso: '2026-06-05',
        now: now,
      );
      expect(today.canEditStart, isFalse);
      expect(today.canEditEnd, isTrue);

      final past = tripDatesEditability(
        lifecycle: TripLifecycle.active,
        startDateIso: '2026-01-01',
        now: now,
      );
      expect(past.canEditStart, isFalse);
      expect(past.canEditEnd, isTrue);
    });

    test('non-active trips block all date edits', () {
      for (final lifecycle in [
        TripLifecycle.closing,
        TripLifecycle.closed,
        TripLifecycle.cancelled,
        TripLifecycle.unresolved,
      ]) {
        final e = tripDatesEditability(
          lifecycle: lifecycle,
          startDateIso: '2026-12-01',
          now: now,
        );
        expect(e.canEditStart, isFalse, reason: '$lifecycle start');
        expect(e.canEditEnd, isFalse, reason: '$lifecycle end');
        expect(e.any, isFalse, reason: '$lifecycle any');
      }
    });
  });
}
