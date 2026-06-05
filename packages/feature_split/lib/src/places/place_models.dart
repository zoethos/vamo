/// Resolved place row (local Drift + remote `places` table).
class PlaceSummary {
  const PlaceSummary({
    required this.id,
    required this.tripId,
    required this.label,
    this.address,
    this.lat,
    this.lng,
    required this.source,
    required this.confidence,
  });

  final String id;
  final String tripId;
  final String label;
  final String? address;
  final double? lat;
  final double? lng;

  /// `exif` | `receipt` | `both`
  final String source;
  final double confidence;
}

/// Output of pure coordinate/source resolution (testable without geocoder).
class PlaceResolutionCoords {
  const PlaceResolutionCoords({
    required this.lat,
    required this.lng,
    required this.source,
    required this.confidence,
    required this.keepAddressText,
  });

  final double lat;
  final double lng;
  final String source;
  final double confidence;

  /// When EXIF and geocode disagree, address text is still stored.
  final bool keepAddressText;
}

/// Geocoded coordinates from a receipt address line.
class GeocodeCoords {
  const GeocodeCoords({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

String placeConfidenceBucket(double confidence) {
  if (confidence >= 0.8) return 'high';
  if (confidence >= 0.5) return 'medium';
  return 'low';
}
