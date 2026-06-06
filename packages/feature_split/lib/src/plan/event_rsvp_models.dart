import 'plan_models.dart';

enum EventRsvpStatus {
  going,
  maybe,
  declined;

  static EventRsvpStatus parse(String? raw) {
    return EventRsvpStatus.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => EventRsvpStatus.going,
    );
  }
}

class EventRsvpRow {
  const EventRsvpRow({
    required this.id,
    required this.planItemId,
    required this.userId,
    required this.status,
    required this.respondedAt,
  });

  final String id;
  final String planItemId;
  final String userId;
  final EventRsvpStatus status;
  final DateTime respondedAt;
}

class EventRsvpCounts {
  const EventRsvpCounts({
    this.going = 0,
    this.maybe = 0,
    this.declined = 0,
  });

  final int going;
  final int maybe;
  final int declined;

  bool get isEmpty => going == 0 && maybe == 0 && declined == 0;
}

EventRsvpCounts aggregateEventRsvpCounts(Iterable<EventRsvpRow> rows) {
  var going = 0;
  var maybe = 0;
  var declined = 0;
  for (final row in rows) {
    switch (row.status) {
      case EventRsvpStatus.going:
        going++;
      case EventRsvpStatus.maybe:
        maybe++;
      case EventRsvpStatus.declined:
        declined++;
    }
  }
  return EventRsvpCounts(going: going, maybe: maybe, declined: declined);
}

EventRsvpStatus? callerEventRsvpStatus({
  required Iterable<EventRsvpRow> rows,
  required String planItemId,
  required String? userId,
}) {
  if (userId == null) return null;
  for (final row in rows) {
    if (row.planItemId == planItemId && row.userId == userId) {
      return row.status;
    }
  }
  return null;
}

/// Maps stored RSVP status values to localized chip labels for display.
String localizeEventRsvpStatus(
  String raw, {
  required String going,
  required String maybe,
  required String declined,
}) {
  return switch (raw) {
    'going' => going,
    'maybe' => maybe,
    'declined' => declined,
    _ => raw,
  };
}

class PlanItemEventView {
  const PlanItemEventView({
    required this.item,
    required this.counts,
    required this.myStatus,
  });

  final PlanItemSummary item;
  final EventRsvpCounts counts;
  final EventRsvpStatus? myStatus;
}
