/// Trip lifecycle states — mirrors Postgres `trip_lifecycle` enum (S17 / R3).
enum TripLifecycle {
  active,
  cancelled,
  closing,
  closed,
  unresolved;

  static TripLifecycle parse(String? raw) {
    return TripLifecycle.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => TripLifecycle.active,
    );
  }

  /// No new expenses, captures, or trip content edits.
  bool get isReadOnly =>
      this == closed || this == cancelled || this == unresolved;

  /// Settling remains available after close (not when cancelled).
  bool get allowsSettlements => this != cancelled;

  bool get isClosing => this == closing;
}

/// Whether the trip blocks member content writes (expenses, capture, edits).
bool isTripReadOnly(TripLifecycle lifecycle) => lifecycle.isReadOnly;

/// Days left in the 14-day close review window (null if not closing).
int? closeReviewDaysRemaining(DateTime? closeRequestedAt, DateTime now) {
  if (closeRequestedAt == null) return null;
  final deadline = closeRequestedAt.add(const Duration(days: 14));
  final remaining = deadline.difference(now).inDays;
  return remaining < 0 ? 0 : remaining;
}
