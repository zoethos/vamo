import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:app_core/app_core.dart';

import 'place_models.dart';

bool get placeGeocodeSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

Future<GeocodeCoords?> geocodeAddress(String address) async {
  final query = address.trim();
  if (query.isEmpty) return null;
  try {
    final locations = await locationFromAddress(query);
    if (locations.isEmpty) return null;
    final first = locations.first;
    return GeocodeCoords(lat: first.latitude, lng: first.longitude);
  } catch (error, stackTrace) {
    reportAndLog(
      error,
      stackTrace,
      screen: 'places',
      action: 'geocode_address',
      severity: ActionFailureSeverity.degraded,
    );
    return null;
  }
}

Future<ResolvedDestination?> resolveDestination(String query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty || !placeGeocodeSupported) return null;

  try {
    final locations = await locationFromAddress(trimmed);
    if (locations.isEmpty) return null;
    final first = locations.first;
    final coords = GeocodeCoords(lat: first.latitude, lng: first.longitude);
    final placemark = await _placemarkFor(coords);
    return ResolvedDestination(
      label: _destinationLabel(trimmed, placemark),
      subtitle: _destinationSubtitle(placemark, coords),
      coords: coords,
    );
  } catch (error, stackTrace) {
    reportAndLog(
      error,
      stackTrace,
      screen: 'places',
      action: 'resolve_destination',
      severity: ActionFailureSeverity.degraded,
    );
    return null;
  }
}

Future<Placemark?> _placemarkFor(GeocodeCoords coords) async {
  try {
    final placemarks = await placemarkFromCoordinates(coords.lat, coords.lng);
    return placemarks.isEmpty ? null : placemarks.first;
  } catch (error, stackTrace) {
    reportAndLog(
      error,
      stackTrace,
      screen: 'places',
      action: 'reverse_geocode_destination',
      severity: ActionFailureSeverity.degraded,
    );
    return null;
  }
}

String _destinationLabel(String fallback, Placemark? place) {
  if (place == null) return fallback;
  final locality = _firstNonEmpty([
    place.locality,
    place.subAdministrativeArea,
    place.administrativeArea,
  ]);
  final country = _clean(place.country);
  if (locality != null && country != null && locality != country) {
    return '$locality, $country';
  }
  return locality ?? country ?? fallback;
}

String _destinationSubtitle(Placemark? place, GeocodeCoords coords) {
  final parts = <String>[];
  void add(String? value) {
    final clean = _clean(value);
    if (clean == null || parts.contains(clean)) return;
    parts.add(clean);
  }

  add(place?.subLocality);
  add(place?.subAdministrativeArea);
  add(place?.administrativeArea);
  add(place?.country);
  if (parts.isNotEmpty) return parts.take(3).join(' · ');
  return '${coords.lat.toStringAsFixed(4)}, ${coords.lng.toStringAsFixed(4)}';
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final clean = _clean(value);
    if (clean != null) return clean;
  }
  return null;
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
