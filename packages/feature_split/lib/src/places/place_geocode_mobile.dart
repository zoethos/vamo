import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

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
  } catch (_) {
    return null;
  }
}
