import 'package:flutter/foundation.dart';

import '../capture/capture_models.dart';
import '../expenses/expense_models.dart';
import '../places/place_models.dart';
import '../plan/plan_models.dart';

/// What a map marker represents. Drives its color/icon in the view layer; kept
/// here so the aggregator stays pure (no Flutter `Color`/`IconData` imports).
enum MapMomentKind { visit, expense, memory }

/// A single trip-scoped point on the journey map. Anything without coordinates
/// is never turned into a moment, so `lat`/`lng` are non-null by construction.
@immutable
class MapMoment {
  const MapMoment({
    required this.id,
    required this.kind,
    required this.lat,
    required this.lng,
    required this.title,
    this.at,
    this.thumbnailPath,
  });

  final String id;
  final MapMomentKind kind;
  final double lat;
  final double lng;
  final String title;

  /// When the moment happened, if known. Drives chronological ordering, the
  /// route polyline, and the day scrubber. Moments without a timestamp still
  /// render as markers but are excluded from the route and per-day filtering.
  final DateTime? at;

  /// Local file path to a thumbnail (memories only), if cached.
  final String? thumbnailPath;
}

/// Aggregates the three trip-scoped sources into ordered [MapMoment]s,
/// **dropping anything without coordinates**. Timed moments come first in
/// chronological order; untimed moments follow in stable insertion order.
///
/// Sources, per the Trip Map P0 slice:
/// - Placed **Visits** — `visit` plan items whose metadata carries lat/lng.
/// - **Expenses with a place** — joined `place_id -> places.lat/lng` only.
///   `expenses.captured_lat/lng` is deliberately ignored (it can be receipt/
///   photo EXIF — where the image was taken, not where the purchase happened).
/// - **Geotagged memories** — trip photos with EXIF capture coordinates.
List<MapMoment> buildTripMapMoments({
  List<PlanItemSummary> planItems = const [],
  List<ExpenseSummary> expenses = const [],
  Map<String, PlaceSummary> placesById = const {},
  List<TripPhotoView> photos = const [],
}) {
  final moments = <MapMoment>[];

  for (final item in planItems) {
    if (item.kind != PlanItemKind.visit) continue;
    final meta = parseVisitPlaceMetadata(item.metadata);
    if (meta == null || !meta.hasCoords) continue;
    moments.add(
      MapMoment(
        id: 'visit:${item.id}',
        kind: MapMomentKind.visit,
        lat: meta.lat!,
        lng: meta.lng!,
        title: meta.placeLabel.isNotEmpty ? meta.placeLabel : item.title,
        at: item.startsAt,
      ),
    );
  }

  for (final expense in expenses) {
    final placeId = expense.placeId;
    if (placeId == null) continue;
    final place = placesById[placeId];
    if (place?.lat == null || place?.lng == null) continue;
    moments.add(
      MapMoment(
        id: 'expense:${expense.id}',
        kind: MapMomentKind.expense,
        lat: place!.lat!,
        lng: place.lng!,
        title: expense.placeLabel?.isNotEmpty == true
            ? expense.placeLabel!
            : (place.label.isNotEmpty ? place.label : expense.description),
        at: expense.spentAt,
      ),
    );
  }

  for (final photo in photos) {
    if (photo.capturedLat == null || photo.capturedLng == null) continue;
    moments.add(
      MapMoment(
        id: 'memory:${photo.id}',
        kind: MapMomentKind.memory,
        lat: photo.capturedLat!,
        lng: photo.capturedLng!,
        title: photo.caption?.isNotEmpty == true ? photo.caption! : '',
        at: photo.mediaCapturedAt ?? photo.capturedAt,
        thumbnailPath: photo.displayPath,
      ),
    );
  }

  return orderMoments(moments);
}

/// Stable chronological ordering: timed moments ascending by [MapMoment.at],
/// then untimed moments in their original order. Dart's [List.sort] is not
/// guaranteed stable, so we partition instead of sorting in place.
List<MapMoment> orderMoments(List<MapMoment> moments) {
  final timed = moments.where((m) => m.at != null).toList()
    ..sort((a, b) => a.at!.compareTo(b.at!));
  final untimed = moments.where((m) => m.at == null).toList();
  return [...timed, ...untimed];
}

/// Inclusive number of days the trip spans, from date-only `start`/`end`.
/// Returns at least 1 when either bound is missing or inverted.
int tripDayCount(DateTime? start, DateTime? end) {
  if (start == null || end == null) return 1;
  final days = _dateOnly(end).difference(_dateOnly(start)).inDays + 1;
  return days < 1 ? 1 : days;
}

/// Moments that fall on the given 0-based [dayIndex] relative to [tripStart].
/// Untimed moments belong to no specific day and are therefore excluded.
List<MapMoment> momentsForDay(
  List<MapMoment> moments, {
  required DateTime tripStart,
  required int dayIndex,
}) {
  final target = _dateOnly(tripStart).add(Duration(days: dayIndex));
  return moments.where((m) {
    final at = m.at;
    if (at == null) return false;
    return _sameDate(at.toLocal(), target);
  }).toList();
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
