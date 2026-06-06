import 'package:app_core/app_core.dart';

/// Overflow-menu lifecycle actions (S17.1).
enum TripLifecycleMenuAction {
  markDone,
  requestClose,
  cancelTrip,
}

/// Which lifecycle entries belong in the trip overflow menu for this phase.
List<TripLifecycleMenuAction> tripLifecycleMenuActions({
  required TripPhase phase,
  required bool isOwner,
  required bool memberAlreadyDone,
}) {
  switch (phase) {
    case TripPhase.preStart:
      if (isOwner) return const [TripLifecycleMenuAction.cancelTrip];
      return const [];
    case TripPhase.ongoing:
      final actions = <TripLifecycleMenuAction>[];
      if (!memberAlreadyDone) {
        actions.add(TripLifecycleMenuAction.markDone);
      }
      if (isOwner) {
        actions.add(TripLifecycleMenuAction.requestClose);
      }
      return actions;
    case TripPhase.closing:
    case TripPhase.readOnly:
      return const [];
  }
}
