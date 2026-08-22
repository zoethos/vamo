import 'package:feature_split/src/plan/plan_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tripId = 'trip-1';
  final now = DateTime.utc(2026, 8, 11, 9);

  PlanItemSummary item({
    required String id,
    DateTime? startsAt,
    int position = 0,
  }) =>
      PlanItemSummary(
        id: id,
        tripId: tripId,
        kind: PlanItemKind.activity,
        title: id,
        startsAt: startsAt,
        position: position,
      );

  test('next dated plan item ignores undated and already-started itinerary rows', () {
    final next = nextDatedPlanItem([
      item(id: 'undated'),
      item(id: 'past', startsAt: now.subtract(const Duration(minutes: 1))),
      item(id: 'tomorrow', startsAt: now.add(const Duration(days: 1))),
      item(id: 'today', startsAt: now.add(const Duration(hours: 2))),
    ], now: now);

    expect(next?.id, 'today');
  });

  test('next dated plan item has stable itinerary tie breakers', () {
    final startsAt = now.add(const Duration(hours: 2));
    final next = nextDatedPlanItem([
      item(id: 'later-position', startsAt: startsAt, position: 2),
      item(id: 'first-position', startsAt: startsAt, position: 1),
    ], now: now);

    expect(next?.id, 'first-position');
  });
}
