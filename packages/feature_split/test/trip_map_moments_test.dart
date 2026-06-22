import 'package:feature_split/src/capture/capture_models.dart';
import 'package:feature_split/src/expenses/expense_governance.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/map/trip_map_moments.dart';
import 'package:feature_split/src/places/place_models.dart';
import 'package:feature_split/src/plan/plan_models.dart';
import 'package:flutter_test/flutter_test.dart';

PlanItemSummary _visit({
  required String id,
  required String label,
  double? lat,
  double? lng,
  DateTime? startsAt,
}) {
  return PlanItemSummary(
    id: id,
    tripId: 't1',
    kind: PlanItemKind.visit,
    title: label,
    startsAt: startsAt,
    metadata: buildVisitPlaceMetadata(placeLabel: label, lat: lat, lng: lng),
    position: 0,
  );
}

ExpenseSummary _expense({
  required String id,
  String? placeId,
  String? placeLabel,
  required DateTime spentAt,
}) {
  return ExpenseSummary(
    id: id,
    tripId: 't1',
    description: 'desc',
    amountCents: 1000,
    baseCents: 1000,
    currency: 'EUR',
    payerId: 'u1',
    spentAt: spentAt,
    status: ExpenseStatus.committed,
    placeId: placeId,
    placeLabel: placeLabel,
  );
}

PlaceSummary _place({required String id, double? lat, double? lng}) {
  return PlaceSummary(
    id: id,
    tripId: 't1',
    label: 'Place $id',
    lat: lat,
    lng: lng,
    source: 'receipt',
    confidence: 1,
  );
}

TripPhotoView _photo({
  required String id,
  double? lat,
  double? lng,
  DateTime? capturedAt,
  String? caption,
}) {
  return TripPhotoView(
    id: id,
    tripId: 't1',
    caption: caption,
    capturedAt: capturedAt ?? DateTime(2026, 1, 1),
    capturedLat: lat,
    capturedLng: lng,
  );
}

void main() {
  group('buildTripMapMoments', () {
    test('aggregates the three sources and drops coord-less items', () {
      final moments = buildTripMapMoments(
        planItems: [
          _visit(id: 'v1', label: 'Pantheon', lat: 41.9, lng: 12.47),
          _visit(id: 'v2', label: 'No coords'), // dropped — no lat/lng
          PlanItemSummary(
            id: 'a1',
            tripId: 't1',
            kind: PlanItemKind.activity, // not a visit — ignored
            title: 'Dinner',
            position: 1,
          ),
        ],
        expenses: [
          _expense(id: 'e1', placeId: 'p1', spentAt: DateTime(2026, 1, 2)),
          _expense(id: 'e2', placeId: 'pX', spentAt: DateTime(2026, 1, 2)),
          _expense(id: 'e3', spentAt: DateTime(2026, 1, 2)), // no placeId
        ],
        placesById: {
          'p1': _place(id: 'p1', lat: 48.85, lng: 2.35),
          'pX': _place(id: 'pX'), // place exists but has no coords — dropped
        },
        photos: [
          _photo(id: 'm1', lat: 40.0, lng: 14.0),
          _photo(id: 'm2'), // no coords — dropped
        ],
      );

      final ids = moments.map((m) => m.id).toSet();
      expect(ids, {'visit:v1', 'expense:e1', 'memory:m1'});

      final visit = moments.firstWhere((m) => m.id == 'visit:v1');
      expect(visit.kind, MapMomentKind.visit);
      expect(visit.lat, 41.9);
      expect(visit.title, 'Pantheon');
    });

    test('orders timed moments chronologically, untimed last', () {
      final moments = buildTripMapMoments(
        planItems: [
          _visit(
            id: 'late',
            label: 'Late',
            lat: 1,
            lng: 1,
            startsAt: DateTime(2026, 5, 3),
          ),
          _visit(id: 'undated', label: 'Undated', lat: 2, lng: 2),
          _visit(
            id: 'early',
            label: 'Early',
            lat: 3,
            lng: 3,
            startsAt: DateTime(2026, 5, 1),
          ),
        ],
      );

      expect(
        moments.map((m) => m.id).toList(),
        ['visit:early', 'visit:late', 'visit:undated'],
      );
    });
  });

  group('day helpers', () {
    test('tripDayCount is inclusive and defaults to at least 1', () {
      expect(tripDayCount(DateTime(2026, 6, 1), DateTime(2026, 6, 7)), 7);
      expect(tripDayCount(DateTime(2026, 6, 1), DateTime(2026, 6, 1)), 1);
      expect(tripDayCount(null, null), 1);
    });

    test('momentsForDay selects only that day and excludes untimed', () {
      final start = DateTime(2026, 6, 1);
      final moments = buildTripMapMoments(
        planItems: [
          _visit(
            id: 'd0',
            label: 'Day 0',
            lat: 1,
            lng: 1,
            startsAt: DateTime(2026, 6, 1, 10),
          ),
          _visit(
            id: 'd1',
            label: 'Day 1',
            lat: 2,
            lng: 2,
            startsAt: DateTime(2026, 6, 2, 9),
          ),
          _visit(id: 'undated', label: 'Undated', lat: 3, lng: 3),
        ],
      );

      final day0 = momentsForDay(moments, tripStart: start, dayIndex: 0);
      expect(day0.map((m) => m.id), ['visit:d0']);

      final day1 = momentsForDay(moments, tripStart: start, dayIndex: 1);
      expect(day1.map((m) => m.id), ['visit:d1']);
    });
  });
}
