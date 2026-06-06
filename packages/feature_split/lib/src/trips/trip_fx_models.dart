class TripFxRateRow {
  const TripFxRateRow({
    required this.id,
    required this.tripId,
    required this.currency,
    required this.rate,
    required this.source,
    required this.capturedAt,
    required this.capturedBy,
  });

  final String id;
  final String tripId;
  final String currency;
  final double rate;
  final String source;
  final DateTime capturedAt;
  final String capturedBy;
}
