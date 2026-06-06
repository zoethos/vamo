/// Single row in the cross-trip Activity feed (v1 — local Drift data).
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.tripId,
    required this.tripName,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.occurredAt,
    this.rsvpStatus,
  });

  final String id;
  final String tripId;
  final String tripName;
  final ActivityKind kind;
  final String title;
  final String subtitle;
  final DateTime occurredAt;
  final String? rsvpStatus;
}

enum ActivityKind {
  expense,
  memberJoined,
  settlement,
  eventCreated,
  eventRsvp,
}
