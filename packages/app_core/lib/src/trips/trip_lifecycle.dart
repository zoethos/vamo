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

/// UI phase for lifecycle controls (S17.1 — distinct from [TripLifecycle] enum).
enum TripPhase {
  preStart,
  ongoing,
  closing,
  readOnly,
}

DateTime? _parseDateOnly(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// Resolves which lifecycle chrome to show (S17.1).
///
/// Undated active trips are treated as [TripPhase.ongoing].
TripPhase resolveTripPhase({
  required TripLifecycle lifecycle,
  required String? startDateIso,
  required DateTime now,
}) {
  if (lifecycle.isReadOnly) return TripPhase.readOnly;
  if (lifecycle == TripLifecycle.closing) return TripPhase.closing;
  final start = _parseDateOnly(startDateIso);
  if (start != null) {
    final today = DateTime(now.year, now.month, now.day);
    if (start.isAfter(today)) return TripPhase.preStart;
  }
  return TripPhase.ongoing;
}
