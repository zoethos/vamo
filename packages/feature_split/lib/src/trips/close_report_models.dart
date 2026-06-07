import 'package:app_core/app_core.dart';

/// How a member responded to trip close (S22 close report).
enum CloseMemberConsentDisplay {
  accepted,
  objected,
  deemed,
  pending,
  notNotified,
}

CloseMemberConsentDisplay resolveCloseMemberConsent({
  required DateTime? closeAcceptedAt,
  required DateTime? closeObjectedAt,
  required DateTime? closeNotifiedAt,
  required TripLifecycle lifecycle,
  required DateTime now,
}) {
  if (closeAcceptedAt != null) return CloseMemberConsentDisplay.accepted;
  if (closeObjectedAt != null) return CloseMemberConsentDisplay.objected;
  if (closeNotifiedAt != null) {
    final remaining = closeReviewDaysRemainingFromNotice(
      closeNotifiedAt,
      now.toUtc(),
    );
    if (lifecycle == TripLifecycle.closed ||
        lifecycle == TripLifecycle.unresolved ||
        (remaining != null && remaining <= 0)) {
      return CloseMemberConsentDisplay.deemed;
    }
    return CloseMemberConsentDisplay.pending;
  }
  return CloseMemberConsentDisplay.notNotified;
}
