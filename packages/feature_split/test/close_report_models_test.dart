import 'package:app_core/app_core.dart';
import 'package:feature_split/src/trips/close_report_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolveCloseMemberConsent distinguishes accepted objected deemed', () {
    final now = DateTime.utc(2026, 6, 7);
    final notified = now.subtract(const Duration(days: 15));

    expect(
      resolveCloseMemberConsent(
        closeAcceptedAt: now,
        closeObjectedAt: null,
        closeNotifiedAt: notified,
        lifecycle: TripLifecycle.closing,
        now: now,
      ),
      CloseMemberConsentDisplay.accepted,
    );

    expect(
      resolveCloseMemberConsent(
        closeAcceptedAt: null,
        closeObjectedAt: now,
        closeNotifiedAt: notified,
        lifecycle: TripLifecycle.closing,
        now: now,
      ),
      CloseMemberConsentDisplay.objected,
    );

    expect(
      resolveCloseMemberConsent(
        closeAcceptedAt: null,
        closeObjectedAt: null,
        closeNotifiedAt: notified,
        lifecycle: TripLifecycle.closing,
        now: now,
      ),
      CloseMemberConsentDisplay.deemed,
    );

    expect(
      resolveCloseMemberConsent(
        closeAcceptedAt: null,
        closeObjectedAt: null,
        closeNotifiedAt: null,
        lifecycle: TripLifecycle.closing,
        now: now,
      ),
      CloseMemberConsentDisplay.notNotified,
    );
  });

  test('closeReviewDaysRemainingFromNotice uses notice not request', () {
    final notified = DateTime.utc(2026, 6, 1);
    final now = DateTime.utc(2026, 6, 10);
    expect(closeReviewDaysRemainingFromNotice(notified, now), 5);
    expect(closeReviewDaysRemainingFromNotice(null, now), isNull);
  });
}
