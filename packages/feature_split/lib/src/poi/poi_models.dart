import 'package:flutter/material.dart';

enum PoiCategory {
  food,
  lodging,
  attraction,
  museum,
  nature,
  nightlife,
  shopping,
  transport,
  other;

  static PoiCategory parse(String? raw) {
    return PoiCategory.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => PoiCategory.other,
    );
  }

  IconData get icon => switch (this) {
        PoiCategory.food => Icons.restaurant_outlined,
        PoiCategory.lodging => Icons.hotel_outlined,
        PoiCategory.attraction => Icons.attractions_outlined,
        PoiCategory.museum => Icons.museum_outlined,
        PoiCategory.nature => Icons.park_outlined,
        PoiCategory.nightlife => Icons.nightlife_outlined,
        PoiCategory.shopping => Icons.shopping_bag_outlined,
        PoiCategory.transport => Icons.directions_transit_outlined,
        PoiCategory.other => Icons.place_outlined,
      };
}

class PoiSummary {
  const PoiSummary({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    required this.source,
    required this.providerPlaceId,
    this.address,
    this.distanceM,
  });

  final String id;
  final String name;
  final PoiCategory category;
  final double lat;
  final double lng;
  final String source;
  final String providerPlaceId;
  final String? address;
  final int? distanceM;

  static PoiSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = _stringValue(map['id']);
    final name = _stringValue(map['name']);
    final lat = _doubleValue(map['lat']);
    final lng = _doubleValue(map['lng']);
    final source = _stringValue(map['source']);
    final providerPlaceId = _stringValue(map['providerPlaceId']);
    if (id == null ||
        name == null ||
        lat == null ||
        lng == null ||
        source == null ||
        providerPlaceId == null) {
      return null;
    }
    return PoiSummary(
      id: id,
      name: name,
      category: PoiCategory.parse(_stringValue(map['category'])),
      lat: lat,
      lng: lng,
      source: source,
      providerPlaceId: providerPlaceId,
      address: _stringValue(map['address']),
      distanceM: _intValue(map['distanceM']),
    );
  }
}

class PoiDiscoveryResult {
  const PoiDiscoveryResult.available(this.pois)
      : gated = false,
        reason = null;

  const PoiDiscoveryResult.gated(this.reason)
      : gated = true,
        pois = const <PoiSummary>[];

  final bool gated;
  final String? reason;
  final List<PoiSummary> pois;

  bool get isEmpty => !gated && pois.isEmpty;

  static PoiDiscoveryResult? fromFunctionPayload(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map['gated'] == true) {
      return PoiDiscoveryResult.gated(_stringValue(map['reason']));
    }
    if (map['available'] != true) return null;
    final rows = map['pois'];
    if (rows is! List) return const PoiDiscoveryResult.available([]);
    return PoiDiscoveryResult.available(
      rows.map(PoiSummary.fromJson).whereType<PoiSummary>().toList(),
    );
  }
}

String? _stringValue(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _doubleValue(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

int? _intValue(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  if (raw is String) return int.tryParse(raw);
  return null;
}
