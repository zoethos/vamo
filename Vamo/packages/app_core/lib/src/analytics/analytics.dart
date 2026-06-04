import 'package:flutter/foundation.dart';

/// Analytics events — North-Star funnel (layer 1) + product signals (spec §8b).
enum VamoEvent {
  tripCreated('trip_created'),
  memberInvited('member_invited'),
  inviteAccepted('invite_accepted'),
  expenseAdded('expense_added'),
  settleMarked('settle_marked'),
  settleConfirmed('settle_confirmed'),
  snapshotShared('snapshot_shared'),

  screenViewed('screen_viewed'),
  errorShown('error_shown'),
  emptyStateShown('empty_state_shown'),
  flowAbandoned('flow_abandoned'),
  actionFailed('action_failed'),

  plusInterestTapped('plus_interest_tapped'),
  recapInterestTapped('recap_interest_tapped'),
  mapInterestTapped('map_interest_tapped'),
  notifyMeOptedIn('notify_me_opted_in'),

  suggestionSubmitted('suggestion_submitted');

  const VamoEvent(this.name);
  final String name;

  /// Layer 1 — acceptance criterion 6.
  static const northStar = [
    tripCreated,
    memberInvited,
    inviteAccepted,
    expenseAdded,
    settleMarked,
    settleConfirmed,
    snapshotShared,
  ];

  /// Layers 2–4 — acceptance criterion 7.
  static const productSignals = [
    screenViewed,
    errorShown,
    emptyStateShown,
    flowAbandoned,
    actionFailed,
    plusInterestTapped,
    recapInterestTapped,
    mapInterestTapped,
    notifyMeOptedIn,
    suggestionSubmitted,
  ];
}

/// Thin analytics seam. Slice 0 ships a debug-print implementation; the
/// PostHog-backed implementation drops in behind the same interface later
/// without touching call sites.
abstract interface class Analytics {
  void capture(VamoEvent event, {Map<String, Object?> properties});
  Future<void> identify(String userId);
  Future<void> reset();
}

class DebugAnalytics implements Analytics {
  @override
  void capture(VamoEvent event, {Map<String, Object?> properties = const {}}) {
    if (kDebugMode) {
      debugPrint('[analytics] ${event.name} $properties');
    }
  }

  @override
  Future<void> identify(String userId) async {
    if (kDebugMode) debugPrint('[analytics] identify $userId');
  }

  @override
  Future<void> reset() async {
    if (kDebugMode) debugPrint('[analytics] reset');
  }
}
