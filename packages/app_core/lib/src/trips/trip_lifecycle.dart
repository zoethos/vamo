/// Trip lifecycle states — mirrors Postgres `trip_lifecycle` enum (S17 / R3).
enum TripLifecycle {
  active,
  cancelled,
  closing,
  closed,
  unresolved,
  softClosed;

  static TripLifecycle parse(String? raw) {
    if (raw == 'soft_closed') return TripLifecycle.softClosed;
    return TripLifecycle.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => TripLifecycle.active,
    );
  }

  /// Postgres enum literal (snake_case where needed).
  String get dbValue => this == TripLifecycle.softClosed ? 'soft_closed' : name;

  /// No new expenses, captures, or trip content edits.
  bool get isReadOnly =>
      this == closed || this == cancelled || this == unresolved;

  /// Settling remains available after close (not when cancelled).
  bool get allowsSettlements => this != cancelled;

  bool get isClosing => this == closing;
}

/// Whether the trip blocks member content writes (expenses, capture, edits).
bool isTripReadOnly(TripLifecycle lifecycle) => lifecycle.isReadOnly;

/// Days left in the 14-day close review window from member notice (S22).
int? closeReviewDaysRemainingFromNotice(
  DateTime? closeNotifiedAt,
  DateTime now,
) {
  if (closeNotifiedAt == null) return null;
  final deadline = closeNotifiedAt.add(const Duration(days: 14));
  final remaining = deadline.difference(now).inDays;
  return remaining < 0 ? 0 : remaining;
}

/// Days left in the 14-day close review window (null if not closing).
/// Prefer [closeReviewDaysRemainingFromNotice] when notice timestamp is known.
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

/// Which trip dates the owner may edit.
class TripDatesEditability {
  const TripDatesEditability({
    required this.canEditStart,
    required this.canEditEnd,
  });

  final bool canEditStart;
  final bool canEditEnd;

  bool get any => canEditStart || canEditEnd;
}

/// Date-edit rules — deliberately distinct from [resolveTripPhase].
///
/// Editing is owner-only (enforced server-side by `update_trip_dates`) and:
/// - blocked entirely once the trip leaves `active` (closing/closed/etc.);
/// - **not started** (start unset or in the future) → both dates editable,
///   so an undated trip can still have a start date added;
/// - **started** (start today or past) → start is locked, end stays editable.
///
/// Note a null start counts as "not started" here, unlike [resolveTripPhase],
/// which treats an undated active trip as [TripPhase.ongoing].
TripDatesEditability tripDatesEditability({
  required TripLifecycle lifecycle,
  required String? startDateIso,
  required DateTime now,
}) {
  if (lifecycle != TripLifecycle.active) {
    return const TripDatesEditability(canEditStart: false, canEditEnd: false);
  }
  final start = _parseDateOnly(startDateIso);
  final today = DateTime(now.year, now.month, now.day);
  final notStarted = start == null || start.isAfter(today);
  return TripDatesEditability(canEditStart: notStarted, canEditEnd: true);
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
  // soft_closed: same chrome as active for all members; owner banner is separate.
  final start = _parseDateOnly(startDateIso);
  if (start != null) {
    final today = DateTime(now.year, now.month, now.day);
    if (start.isAfter(today)) return TripPhase.preStart;
  }
  return TripPhase.ongoing;
}

/// H-P0 weather badge gate: pre-start trips whose start date is within 7 days.
bool shouldShowWeatherPreview({
  required TripLifecycle lifecycle,
  required String? startDateIso,
  required DateTime now,
}) {
  if (resolveTripPhase(
        lifecycle: lifecycle,
        startDateIso: startDateIso,
        now: now,
      ) !=
      TripPhase.preStart) {
    return false;
  }
  final start = _parseDateOnly(startDateIso);
  if (start == null) return false;
  final today = DateTime(now.year, now.month, now.day);
  return start.difference(today).inDays <= 7;
}
