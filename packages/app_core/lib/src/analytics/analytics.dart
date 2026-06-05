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

  suggestionSubmitted('suggestion_submitted'),

  ocrSuggestionEdited('ocr_suggestion_edited'),
  placeResolved('place_resolved'),
  tripRollupOpened('trip_rollup_opened'),
  qrShown('qr_shown'),
  routeNotFound('route_not_found'),
  closeRequested('close_requested'),
  closeAccepted('close_accepted'),
  closeObjected('close_objected'),
  tripCancelled('trip_cancelled'),
  tripUnresolved('trip_unresolved'),
  planItemCreated('plan_item_created'),
  planItemUpdated('plan_item_updated'),
  planItemDeleted('plan_item_deleted'),
  listItemAdded('list_item_added'),
  listItemChecked('list_item_checked'),
  proposalCreated('proposal_created'),
  proposalCommitted('proposal_committed'),
  proposalCancelled('proposal_cancelled'),
  shareResponse('share_response');

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
        ocrSuggestionEdited,
        placeResolved,
        tripRollupOpened,
        qrShown,
        routeNotFound,
        closeRequested,
        closeAccepted,
        closeObjected,
        tripCancelled,
        tripUnresolved,
        planItemCreated,
        planItemUpdated,
        planItemDeleted,
        listItemAdded,
        listItemChecked,
        proposalCreated,
        proposalCommitted,
        proposalCancelled,
        shareResponse,
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
