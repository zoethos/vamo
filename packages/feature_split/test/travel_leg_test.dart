import 'package:feature_split/src/plan/plan_models.dart';
import 'package:feature_split/src/travel/travel_leg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TravelMode → Plan mapping', () {
    test('train and flight keep their own plan kinds, no transfer subtype', () {
      expect(TravelMode.train.planKind, PlanItemKind.train);
      expect(TravelMode.flight.planKind, PlanItemKind.flight);
      expect(TravelMode.train.transferSubtype, isNull);
      expect(TravelMode.flight.transferSubtype, isNull);
    });

    test('road modes commit to transfer with a best-effort subtype', () {
      for (final mode in [
        TravelMode.car,
        TravelMode.motorbike,
        TravelMode.bike,
        TravelMode.bus,
      ]) {
        expect(mode.planKind, PlanItemKind.transfer);
        expect(mode.transferSubtype, isNotNull);
      }
      expect(TravelMode.car.transferSubtype, TransferSubtype.drive);
      expect(TravelMode.motorbike.transferSubtype, TransferSubtype.drive);
      expect(TravelMode.bike.transferSubtype, TransferSubtype.transit);
      expect(TravelMode.bus.transferSubtype, TransferSubtype.transit);
    });

    test('parse falls back to car for unknown values', () {
      expect(TravelMode.parse('flight'), TravelMode.flight);
      expect(TravelMode.parse('rocket'), TravelMode.car);
      expect(TravelMode.parse(null), TravelMode.car);
    });
  });

  group('ReachLimit', () {
    test('distance and time carry value + type; none is unlimited', () {
      const d = ReachLimit.distanceKm(600);
      expect(d.type, ReachType.distance);
      expect(d.value, 600);
      expect(d.isUnlimited, isFalse);

      const t = ReachLimit.hoursPerDay(5);
      expect(t.type, ReachType.time);
      expect(t.value, 5);

      const none = ReachLimit.none();
      expect(none.isUnlimited, isTrue);
      expect(none.value, isNull);
    });

    test('equality by type + value', () {
      expect(const ReachLimit.distanceKm(300), const ReachLimit.distanceKm(300));
      expect(
        const ReachLimit.distanceKm(300) == const ReachLimit.hoursPerDay(300),
        isFalse,
      );
    });
  });

  group('validateTravelLeg', () {
    final tripStart = DateTime.utc(2026, 7, 1);
    final tripEnd = DateTime.utc(2026, 7, 7);

    test('valid leg inside the trip window has no problems', () {
      final leg = TravelLeg(
        mode: TravelMode.car,
        windowStart: DateTime.utc(2026, 7, 1),
        windowEnd: DateTime.utc(2026, 7, 3),
        reach: const ReachLimit.distanceKm(600),
      );
      expect(
        validateTravelLeg(leg, tripStart: tripStart, tripEnd: tripEnd),
        isEmpty,
      );
    });

    test('end before start is flagged', () {
      final leg = TravelLeg(
        mode: TravelMode.car,
        windowStart: DateTime.utc(2026, 7, 3),
        windowEnd: DateTime.utc(2026, 7, 1),
      );
      expect(
        validateTravelLeg(leg, tripStart: tripStart, tripEnd: tripEnd),
        contains(TravelLegProblem.windowEndBeforeStart),
      );
    });

    test('window outside the trip bounds is flagged once', () {
      final before = TravelLeg(
        mode: TravelMode.bike,
        windowStart: DateTime.utc(2026, 6, 30),
        windowEnd: DateTime.utc(2026, 7, 8),
      );
      final problems =
          validateTravelLeg(before, tripStart: tripStart, tripEnd: tripEnd);
      expect(problems, contains(TravelLegProblem.windowOutsideTrip));
      expect(
        problems.where((p) => p == TravelLegProblem.windowOutsideTrip).length,
        1,
      );
    });

    test('non-positive reach is flagged; unlimited is fine', () {
      final zero = TravelLeg(
        mode: TravelMode.bike,
        reach: const ReachLimit.distanceKm(0),
      );
      expect(
        validateTravelLeg(zero),
        contains(TravelLegProblem.reachNonPositive),
      );
      const unlimited = TravelLeg(mode: TravelMode.flight);
      expect(validateTravelLeg(unlimited), isEmpty);
    });
  });

  group('TravelLeg.copyWith', () {
    test('clears windows explicitly and swaps reach', () {
      final leg = TravelLeg(
        mode: TravelMode.car,
        windowStart: DateTime.utc(2026, 7, 1),
        reach: const ReachLimit.distanceKm(600),
      );
      final cleared = leg.copyWith(
        clearWindowStart: true,
        reach: const ReachLimit.hoursPerDay(5),
      );
      expect(cleared.windowStart, isNull);
      expect(cleared.reach, const ReachLimit.hoursPerDay(5));
      expect(cleared.mode, TravelMode.car);
    });
  });
}
