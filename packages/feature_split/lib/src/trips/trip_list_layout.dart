import 'trips_models.dart';
import 'trip_format.dart';

/// Featured + compact split for the My Trips hierarchy (S35).
class TripListLayout {
  const TripListLayout({
    this.featured,
    required this.upcoming,
    required this.past,
    required this.other,
  });

  final TripSummary? featured;
  final List<TripSummary> upcoming;
  final List<TripSummary> past;
  final List<TripSummary> other;

  bool get hasFeatured => featured != null;
}

TripListLayout layoutTripsForMyTrips(List<TripSummary> trips, {DateTime? now}) {
  final referenceNow = now ?? DateTime.now();
  final upcoming = <TripSummary>[];
  final past = <TripSummary>[];
  final other = <TripSummary>[];

  for (final trip in trips) {
    final start = parseTripDate(trip.startDate);
    final end = parseTripDate(trip.endDate) ?? start;
    if (start != null && start.isAfter(referenceNow)) {
      upcoming.add(trip);
    } else if (end != null && end.isBefore(referenceNow)) {
      past.add(trip);
    } else {
      other.add(trip);
    }
  }

  upcoming.sort((a, b) {
    final as = parseTripDate(a.startDate);
    final bs = parseTripDate(b.startDate);
    if (as == null && bs == null) return 0;
    if (as == null) return 1;
    if (bs == null) return -1;
    return as.compareTo(bs);
  });

  past.sort((a, b) {
    final ae = parseTripDate(a.endDate) ?? parseTripDate(a.startDate);
    final be = parseTripDate(b.endDate) ?? parseTripDate(b.startDate);
    if (ae == null && be == null) return 0;
    if (ae == null) return 1;
    if (be == null) return -1;
    return be.compareTo(ae);
  });

  TripSummary? featured;
  final compactUpcoming = <TripSummary>[];
  if (upcoming.isNotEmpty) {
    featured = upcoming.first;
    if (upcoming.length > 1) {
      compactUpcoming.addAll(upcoming.sublist(1));
    }
  }

  return TripListLayout(
    featured: featured,
    upcoming: compactUpcoming,
    past: past,
    other: other,
  );
}
