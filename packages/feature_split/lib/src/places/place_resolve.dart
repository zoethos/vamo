import 'dart:math' as math;

import 'place_models.dart';

const placeDedupeRadiusMeters = 100;
const placeExifAgreementRadiusMeters = 500;

/// Haversine distance in meters between two WGS84 points.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}

double _toRadians(double degrees) => degrees * math.pi / 180;

/// Cross-check receipt geocode with EXIF GPS per W2 place-resolution rules.
PlaceResolutionCoords? resolvePlaceCoordinates({
  GeocodeCoords? geocoded,
  double? exifLat,
  double? exifLng,
}) {
  final hasExif = exifLat != null && exifLng != null;

  if (geocoded != null && hasExif) {
    final meters = distanceMeters(
      geocoded.lat,
      geocoded.lng,
      exifLat,
      exifLng,
    );
    if (meters < placeExifAgreementRadiusMeters) {
      return PlaceResolutionCoords(
        lat: exifLat,
        lng: exifLng,
        source: 'both',
        confidence: 0.9,
        keepAddressText: true,
      );
    }
    return PlaceResolutionCoords(
      lat: exifLat,
      lng: exifLng,
      source: 'exif',
      confidence: 0.55,
      keepAddressText: true,
    );
  }

  if (geocoded != null) {
    return PlaceResolutionCoords(
      lat: geocoded.lat,
      lng: geocoded.lng,
      source: 'receipt',
      confidence: 0.6,
      keepAddressText: true,
    );
  }

  if (hasExif) {
    return PlaceResolutionCoords(
      lat: exifLat,
      lng: exifLng,
      source: 'exif',
      confidence: 0.55,
      keepAddressText: false,
    );
  }

  return null;
}

/// Reuse an existing trip place when label matches and coords are ~100m apart.
String? findDuplicatePlaceId({
  required List<PlaceSummary> existing,
  required String label,
  required double? lat,
  required double? lng,
}) {
  final normLabel = label.trim().toLowerCase();
  if (normLabel.isEmpty) return null;

  for (final place in existing) {
    if (place.label.trim().toLowerCase() != normLabel) continue;
    if (lat == null ||
        lng == null ||
        place.lat == null ||
        place.lng == null) {
      return place.id;
    }
    if (distanceMeters(lat, lng, place.lat!, place.lng!) <=
        placeDedupeRadiusMeters) {
      return place.id;
    }
  }
  return null;
}
