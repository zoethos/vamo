import 'package:app_core/app_core.dart';
import 'package:feature_split/src/trips/trip_lifecycle_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tripLifecycleMenuActions', () {
    test('pre-start owner sees cancel only', () {
      expect(
        tripLifecycleMenuActions(
          phase: TripPhase.preStart,
          isOwner: true,
          memberAlreadyDone: false,
        ),
        [TripLifecycleMenuAction.cancelTrip],
      );
    });

    test('pre-start member sees no lifecycle menu items', () {
      expect(
        tripLifecycleMenuActions(
          phase: TripPhase.preStart,
          isOwner: false,
          memberAlreadyDone: false,
        ),
        isEmpty,
      );
    });

    test('ongoing owner sees done and request close', () {
      expect(
        tripLifecycleMenuActions(
          phase: TripPhase.ongoing,
          isOwner: true,
          memberAlreadyDone: false,
        ),
        [
          TripLifecycleMenuAction.markDone,
          TripLifecycleMenuAction.requestClose,
        ],
      );
    });

    test('ongoing member sees done only', () {
      expect(
        tripLifecycleMenuActions(
          phase: TripPhase.ongoing,
          isOwner: false,
          memberAlreadyDone: false,
        ),
        [TripLifecycleMenuAction.markDone],
      );
    });

    test('ongoing hides done after member marked complete', () {
      expect(
        tripLifecycleMenuActions(
          phase: TripPhase.ongoing,
          isOwner: true,
          memberAlreadyDone: true,
        ),
        [TripLifecycleMenuAction.requestClose],
      );
    });

    test('closing and read-only have no overflow items', () {
      expect(
        tripLifecycleMenuActions(
          phase: TripPhase.closing,
          isOwner: true,
          memberAlreadyDone: false,
        ),
        isEmpty,
      );
      expect(
        tripLifecycleMenuActions(
          phase: TripPhase.readOnly,
          isOwner: true,
          memberAlreadyDone: false,
        ),
        isEmpty,
      );
    });
  });
}
