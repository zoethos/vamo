import 'package:flutter/material.dart';

import '../plan/plan_models.dart';

/// Transport mode for an advanced travel leg.
///
/// A leg is `mode · window · reach` — the envelope the AI route-drafter solves
/// inside. [planKind]/[transferSubtype] describe how a leg commits to the Plan
/// once a draft is accepted (Slice 3); they are pure mappings here.
enum TravelMode {
  car,
  motorbike,
  bike,
  train,
  flight,
  bus;

  static TravelMode parse(String? raw) => TravelMode.values.firstWhere(
        (m) => m.name == raw,
        orElse: () => TravelMode.car,
      );

  IconData get icon => switch (this) {
        TravelMode.car => Icons.directions_car_outlined,
        TravelMode.motorbike => Icons.two_wheeler_outlined,
        TravelMode.bike => Icons.pedal_bike_outlined,
        TravelMode.train => Icons.train_outlined,
        TravelMode.flight => Icons.flight_outlined,
        TravelMode.bus => Icons.directions_bus_outlined,
      };

  /// Plan kind this mode commits to when an AI draft lands in the Plan.
  PlanItemKind get planKind => switch (this) {
        TravelMode.train => PlanItemKind.train,
        TravelMode.flight => PlanItemKind.flight,
        TravelMode.car ||
        TravelMode.motorbike ||
        TravelMode.bike ||
        TravelMode.bus =>
          PlanItemKind.transfer,
      };

  /// Transfer subtype for modes that commit to [PlanItemKind.transfer]; null
  /// for train/flight (their own kinds). Best-effort against the current
  /// [TransferSubtype] set — extend it with bike/bus/motorbike in Slice 3.
  TransferSubtype? get transferSubtype => switch (this) {
        TravelMode.car || TravelMode.motorbike => TransferSubtype.drive,
        TravelMode.bike || TravelMode.bus => TransferSubtype.transit,
        TravelMode.train || TravelMode.flight => null,
      };
}

/// What a leg's reach limit caps.
enum ReachType { distance, time }

/// Per-leg reach envelope: max distance (canonical kilometres) or max
/// hours/day. [ReachLimit.none] means uncapped (e.g. flight legs).
@immutable
class ReachLimit {
  const ReachLimit.distanceKm(double km)
      : type = ReachType.distance,
        value = km;

  const ReachLimit.hoursPerDay(double hours)
      : type = ReachType.time,
        value = hours;

  const ReachLimit.none()
      : type = ReachType.distance,
        value = null;

  final ReachType type;

  /// Kilometres for [ReachType.distance], hours/day for [ReachType.time];
  /// null = no limit.
  final double? value;

  bool get isUnlimited => value == null;

  @override
  bool operator ==(Object other) =>
      other is ReachLimit && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);
}

/// A single ordered travel leg: how you move, when you're free, and how far you
/// can reach. Windows are inclusive day bounds (times optional in P0).
@immutable
class TravelLeg {
  const TravelLeg({
    required this.mode,
    this.windowStart,
    this.windowEnd,
    this.reach = const ReachLimit.none(),
  });

  final TravelMode mode;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final ReachLimit reach;

  TravelLeg copyWith({
    TravelMode? mode,
    DateTime? windowStart,
    bool clearWindowStart = false,
    DateTime? windowEnd,
    bool clearWindowEnd = false,
    ReachLimit? reach,
  }) {
    return TravelLeg(
      mode: mode ?? this.mode,
      windowStart:
          clearWindowStart ? null : (windowStart ?? this.windowStart),
      windowEnd: clearWindowEnd ? null : (windowEnd ?? this.windowEnd),
      reach: reach ?? this.reach,
    );
  }
}

/// A validation problem on a single leg.
enum TravelLegProblem { windowEndBeforeStart, windowOutsideTrip, reachNonPositive }

/// Deterministic, AI-free leg validation: window ordering, trip-bound
/// containment, and a positive reach cap. Returns an empty set when valid.
Set<TravelLegProblem> validateTravelLeg(
  TravelLeg leg, {
  DateTime? tripStart,
  DateTime? tripEnd,
}) {
  final problems = <TravelLegProblem>{};
  final start = leg.windowStart;
  final end = leg.windowEnd;

  if (start != null && end != null && end.isBefore(start)) {
    problems.add(TravelLegProblem.windowEndBeforeStart);
  }
  if (tripStart != null && start != null && start.isBefore(tripStart)) {
    problems.add(TravelLegProblem.windowOutsideTrip);
  }
  if (tripEnd != null && end != null && end.isAfter(tripEnd)) {
    problems.add(TravelLegProblem.windowOutsideTrip);
  }
  if (!leg.reach.isUnlimited && (leg.reach.value ?? 0) <= 0) {
    problems.add(TravelLegProblem.reachNonPositive);
  }
  return problems;
}
