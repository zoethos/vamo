import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:geocoding/geocoding.dart';
import 'package:app_core/app_core.dart';
import 'package:http/http.dart' as http;

import 'place_models.dart';

const _openMeteoGeocodingUrl = 'https://geocoding-api.open-meteo.com/v1/search';
const _geocodeTimeout = Duration(seconds: 8);

bool get placeGeocodeSupported => true;

bool get _platformGeocodeSupported => Platform.isAndroid || Platform.isIOS;

Future<GeocodeCoords?> geocodeAddress(String address) async {
  final query = address.trim();
  if (query.isEmpty) return null;

  if (_platformGeocodeSupported) {
    final coords = await _platformGeocodeAddress(query);
    if (coords != null) return coords;
  }

  final resolved = await _resolveWithOpenMeteo(query);
  return resolved?.coords;
}

Future<GeocodeCoords?> _platformGeocodeAddress(String query) async {
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
  if (trimmed.isEmpty) return null;

  if (_platformGeocodeSupported) {
    final resolved = await _resolveWithPlatformGeocoder(trimmed);
    if (resolved != null) return resolved;
  }

  return _resolveWithOpenMeteo(trimmed);
}

Future<ResolvedDestination?> _resolveWithPlatformGeocoder(String query) async {
  try {
    final locations = await locationFromAddress(query);
    if (locations.isEmpty) return null;
    final first = locations.first;
    final coords = GeocodeCoords(lat: first.latitude, lng: first.longitude);
    final placemark = await _placemarkFor(coords);
    return ResolvedDestination(
      label: _destinationLabel(query, placemark),
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

Future<ResolvedDestination?> _resolveWithOpenMeteo(String query) async {
  try {
    final uri = Uri.parse(_openMeteoGeocodingUrl).replace(
      queryParameters: {
        'name': query,
        'count': '10',
        'language': 'en',
        'format': 'json',
      },
    );
    final response = await http.get(uri).timeout(_geocodeTimeout);
    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body);
    final row = _bestOpenMeteoResult(
      body is Map<String, dynamic> ? body['results'] : null,
      query,
    );
    if (row == null) return null;

    final lat = _toDouble(row['latitude']);
    final lng = _toDouble(row['longitude']);
    final name = _clean(row['name'] as String?);
    if (lat == null || lng == null || name == null) return null;

    final country = _clean(row['country'] as String?);
    final admin1 = _clean(row['admin1'] as String?);
    final admin2 = _clean(row['admin2'] as String?);
    final coords = GeocodeCoords(lat: lat, lng: lng);
    final label = country == null || country == name ? name : '$name, $country';
    final subtitleParts = <String?>[admin2, admin1, country]
        .whereType<String>()
        .where((part) => part != name)
        .toList();

    return ResolvedDestination(
      label: label,
      subtitle: subtitleParts.isEmpty
          ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
          : subtitleParts.take(3).join(' · '),
      coords: coords,
    );
  } catch (error, stackTrace) {
    reportAndLog(
      error,
      stackTrace,
      screen: 'places',
      action: 'resolve_destination_open_meteo',
      severity: ActionFailureSeverity.degraded,
    );
    return null;
  }
}

Map<String, dynamic>? _bestOpenMeteoResult(Object? results, String query) {
  if (results is! List) return null;
  Map<String, dynamic>? best;
  var bestScore = -1;
  for (final result in results) {
    if (result is! Map) continue;
    final row = result.cast<String, dynamic>();
    final score = _openMeteoScore(row, query);
    if (score > bestScore) {
      best = row;
      bestScore = score;
    }
  }
  return best;
}

int _openMeteoScore(Map<String, dynamic> row, String query) {
  final queryNorm = _normalize(query);
  final queryTokens = _tokens(query);
  final name = _clean(row['name'] as String?);
  final country = _clean(row['country'] as String?);
  final admin1 = _clean(row['admin1'] as String?);
  final admin2 = _clean(row['admin2'] as String?);
  final featureCode = _clean(row['feature_code'] as String?);
  final disambiguationTokens = queryTokens.difference(_tokens(name));
  var score = 0;

  final nameNorm = _normalize(name);
  if (nameNorm == queryNorm) {
    score += 100;
  } else if (nameNorm.startsWith(queryNorm)) {
    score += 55;
  } else if (nameNorm.contains(queryNorm)) {
    score += 25;
  }

  for (final locationPart in [country, admin1, admin2]) {
    final locationTokens = _tokens(locationPart);
    if (disambiguationTokens.any(locationTokens.contains)) {
      score += 80;
    }
  }

  score += switch (featureCode) {
    'PPLC' => 65,
    'PPLA' => 55,
    'PPLA2' => 48,
    'PPLA3' => 44,
    'PPL' => 35,
    String value when value.startsWith('PPL') => 24,
    _ => 0,
  };

  score += _destinationCountryPrior[country] ?? 0;
  final population = _toInt(row['population']);
  if (population != null) {
    if (population >= 1000000) {
      score += 30;
    } else if (population >= 100000) {
      score += 20;
    } else if (population >= 10000) {
      score += 10;
    } else if (population >= 1000) {
      score += 5;
    }
  }

  return score;
}

double? _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _toInt(Object? value) {
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

String _normalize(String? value) => (_clean(value) ?? '').toLowerCase();

Set<String> _tokens(String? value) => _normalize(value)
    .split(RegExp(r'[^a-z0-9]+'))
    .where((token) => token.length > 2)
    .toSet();

const _destinationCountryPrior = <String, int>{
  'Italy': 42,
  'France': 38,
  'Spain': 34,
  'Greece': 32,
  'Japan': 32,
  'United Kingdom': 30,
  'United States': 30,
  'Portugal': 28,
  'Thailand': 28,
  'Turkey': 26,
  'Croatia': 24,
  'Mexico': 24,
  'Indonesia': 22,
  'India': 22,
  'Egypt': 22,
  'Morocco': 22,
  'Netherlands': 20,
  'Germany': 20,
  'Australia': 18,
  'Canada': 18,
};

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
