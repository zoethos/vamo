import 'package:feature_split/src/plan/event_rsvp_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aggregateEventRsvpCounts tallies going, maybe, declined', () {
    final rows = [
      EventRsvpRow(
        id: '1',
        planItemId: 'event-1',
        userId: 'u1',
        status: EventRsvpStatus.going,
        respondedAt: DateTime.utc(2026, 6, 5),
      ),
      EventRsvpRow(
        id: '2',
        planItemId: 'event-1',
        userId: 'u2',
        status: EventRsvpStatus.going,
        respondedAt: DateTime.utc(2026, 6, 5),
      ),
      EventRsvpRow(
        id: '3',
        planItemId: 'event-1',
        userId: 'u3',
        status: EventRsvpStatus.maybe,
        respondedAt: DateTime.utc(2026, 6, 5),
      ),
      EventRsvpRow(
        id: '4',
        planItemId: 'event-1',
        userId: 'u4',
        status: EventRsvpStatus.declined,
        respondedAt: DateTime.utc(2026, 6, 5),
      ),
    ];

    final counts = aggregateEventRsvpCounts(rows);
    expect(counts.going, 2);
    expect(counts.maybe, 1);
    expect(counts.declined, 1);
    expect(counts.isEmpty, isFalse);
  });

  test('callerEventRsvpStatus returns null when no row (not responded)', () {
    final status = callerEventRsvpStatus(
      rows: const [],
      planItemId: 'event-1',
      userId: 'u1',
    );
    expect(status, isNull);
  });

  test('callerEventRsvpStatus returns status when row exists', () {
    final status = callerEventRsvpStatus(
      rows: [
        EventRsvpRow(
          id: '1',
          planItemId: 'event-1',
          userId: 'u1',
          status: EventRsvpStatus.maybe,
          respondedAt: DateTime.utc(2026, 6, 5),
        ),
      ],
      planItemId: 'event-1',
      userId: 'u1',
    );
    expect(status, EventRsvpStatus.maybe);
  });

  test('localizeEventRsvpStatus maps enum values to chip labels', () {
    expect(
      localizeEventRsvpStatus(
        'going',
        going: 'Going',
        maybe: 'Maybe',
        declined: 'Declined',
      ),
      'Going',
    );
    expect(
      localizeEventRsvpStatus(
        'maybe',
        going: 'Going',
        maybe: 'Maybe',
        declined: 'Declined',
      ),
      'Maybe',
    );
    expect(
      localizeEventRsvpStatus(
        'declined',
        going: 'Going',
        maybe: 'Maybe',
        declined: 'Declined',
      ),
      'Declined',
    );
  });
}
