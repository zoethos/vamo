import 'dart:convert';

import 'package:flutter/material.dart';

enum PlanItemKind {
  lodging,
  flight,
  train,
  activity,
  visit,
  transfer,
  other;

  static PlanItemKind parse(String? raw) {
    return PlanItemKind.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => PlanItemKind.other,
    );
  }

  IconData get icon => switch (this) {
        PlanItemKind.lodging => Icons.hotel_outlined,
        PlanItemKind.flight => Icons.flight_outlined,
        PlanItemKind.train => Icons.train_outlined,
        PlanItemKind.activity => Icons.local_activity_outlined,
        PlanItemKind.visit => Icons.place_outlined,
        PlanItemKind.transfer => Icons.sync_alt_outlined,
        PlanItemKind.other => Icons.event_note_outlined,
      };
}

enum TransferSubtype {
  carRental('car_rental'),
  train('train'),
  transit('transit'),
  drive('drive'),
  flight('flight');

  const TransferSubtype(this.wireName);

  final String wireName;

  static TransferSubtype parse(String? raw) {
    return TransferSubtype.values.firstWhere(
      (v) => v.wireName == raw,
      orElse: () => TransferSubtype.transit,
    );
  }
}

class PlanItemSummary {
  const PlanItemSummary({
    required this.id,
    required this.tripId,
    required this.kind,
    required this.title,
    this.notes,
    this.startsAt,
    this.endsAt,
    this.metadata = const <String, Object?>{},
    required this.position,
  });

  final String id;
  final String tripId;
  final PlanItemKind kind;
  final String title;
  final String? notes;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final Map<String, Object?> metadata;
  final int position;
}

class PlanItemCapabilities {
  const PlanItemCapabilities({
    required this.kind,
    this.waveMin = 2,
    this.supportsRsvp = false,
    this.suggestsPois = false,
    this.hasLiveStatus = false,
    this.hasCheckTimes = false,
    this.sellsTickets = false,
    this.hasDetailsForm = false,
  });

  final PlanItemKind kind;
  final int waveMin;
  final bool supportsRsvp;
  final bool suggestsPois;
  final bool hasLiveStatus;
  final bool hasCheckTimes;
  final bool sellsTickets;
  final bool hasDetailsForm;

  static PlanItemCapabilities fallbackFor(PlanItemKind kind) {
    return PlanItemCapabilities(
      kind: kind,
      supportsRsvp: kind == PlanItemKind.activity,
      suggestsPois: kind == PlanItemKind.activity || kind == PlanItemKind.visit,
      hasLiveStatus: kind == PlanItemKind.flight ||
          kind == PlanItemKind.train ||
          kind == PlanItemKind.transfer,
      hasCheckTimes: kind == PlanItemKind.transfer,
      hasDetailsForm:
          kind == PlanItemKind.visit || kind == PlanItemKind.transfer,
    );
  }

  static Map<PlanItemKind, PlanItemCapabilities> fallbackByKind() {
    return {
      for (final kind in PlanItemKind.values) kind: fallbackFor(kind),
    };
  }
}

class TripListItemSummary {
  const TripListItemSummary({
    required this.id,
    required this.tripId,
    required this.listName,
    required this.label,
    this.checkedBy,
    this.checkedAt,
    required this.position,
  });

  final String id;
  final String tripId;
  final String listName;
  final String label;
  final String? checkedBy;
  final DateTime? checkedAt;
  final int position;

  bool get isChecked => checkedBy != null;
}

class PlanItemInput {
  const PlanItemInput({
    required this.tripId,
    required this.kind,
    required this.title,
    this.notes,
    this.startsAt,
    this.endsAt,
    this.metadata = const <String, Object?>{},
  });

  final String tripId;
  final PlanItemKind kind;
  final String title;
  final String? notes;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final Map<String, Object?> metadata;
}

class VisitPlaceMetadata {
  const VisitPlaceMetadata({
    required this.placeLabel,
    this.address,
    this.lat,
    this.lng,
    this.placeId,
  });

  final String placeLabel;
  final String? address;
  final double? lat;
  final double? lng;
  final String? placeId;

  bool get hasCoords => lat != null && lng != null;
}

class TransferMetadata {
  const TransferMetadata({
    required this.subtype,
    this.origin,
    this.destination,
    this.provider,
    this.reference,
  });

  final TransferSubtype subtype;
  final String? origin;
  final String? destination;
  final String? provider;
  final String? reference;
}

VisitPlaceMetadata? parseVisitPlaceMetadata(Object? raw) {
  final metadata = parsePlanMetadata(raw);
  final placeLabel = _stringValue(metadata['place_label']);
  if (placeLabel == null) return null;

  return VisitPlaceMetadata(
    placeLabel: placeLabel,
    address: _stringValue(metadata['address']),
    lat: _doubleValue(metadata['lat']),
    lng: _doubleValue(metadata['lng']),
    placeId: _stringValue(metadata['place_id']),
  );
}

Map<String, Object?> buildVisitPlaceMetadata({
  required String placeLabel,
  String? address,
  double? lat,
  double? lng,
  String? placeId,
}) {
  final normalizedLabel = placeLabel.trim();
  final normalizedAddress = address?.trim();
  final normalizedPlaceId = placeId?.trim();
  return <String, Object?>{
    'place_label': normalizedLabel,
    if (normalizedAddress != null && normalizedAddress.isNotEmpty)
      'address': normalizedAddress,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    if (normalizedPlaceId != null && normalizedPlaceId.isNotEmpty)
      'place_id': normalizedPlaceId,
  };
}

TransferMetadata? parseTransferMetadata(Object? raw) {
  final metadata = parsePlanMetadata(raw);
  final subtypeRaw = _stringValue(metadata['subtype']);
  if (subtypeRaw == null) return null;

  return TransferMetadata(
    subtype: TransferSubtype.parse(subtypeRaw),
    origin: _stringValue(metadata['origin']),
    destination: _stringValue(metadata['destination']),
    provider: _stringValue(metadata['provider']),
    reference: _stringValue(metadata['reference']),
  );
}

Map<String, Object?> buildTransferMetadata({
  required TransferSubtype subtype,
  String? origin,
  String? destination,
  String? provider,
  String? reference,
}) {
  final normalizedOrigin = origin?.trim();
  final normalizedDestination = destination?.trim();
  final normalizedProvider = provider?.trim();
  final normalizedReference = reference?.trim();
  return <String, Object?>{
    'subtype': subtype.wireName,
    if (normalizedOrigin != null && normalizedOrigin.isNotEmpty)
      'origin': normalizedOrigin,
    if (normalizedDestination != null && normalizedDestination.isNotEmpty)
      'destination': normalizedDestination,
    if (normalizedProvider != null && normalizedProvider.isNotEmpty)
      'provider': normalizedProvider,
    if (normalizedReference != null && normalizedReference.isNotEmpty)
      'reference': normalizedReference,
  };
}

TransferSubtype? legacyTransferSubtypeForKind(PlanItemKind kind) {
  return switch (kind) {
    PlanItemKind.flight => TransferSubtype.flight,
    PlanItemKind.train => TransferSubtype.train,
    _ => null,
  };
}

Map<String, Object?> parsePlanMetadata(Object? raw) {
  if (raw == null) return const <String, Object?>{};
  if (raw is String) {
    if (raw.trim().isEmpty) return const <String, Object?>{};
    try {
      return parsePlanMetadata(jsonDecode(raw));
    } on FormatException {
      return const <String, Object?>{};
    }
  }
  if (raw is Map) {
    return {
      for (final entry in raw.entries)
        if (entry.key != null) entry.key.toString(): entry.value,
    };
  }
  return const <String, Object?>{};
}

String? _stringValue(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _doubleValue(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

String encodePlanMetadata(Map<String, Object?> metadata) {
  return jsonEncode(_sortJsonObject(metadata));
}

Map<String, Object?> _sortJsonObject(Map<String, Object?> value) {
  final entries = value.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return {
    for (final entry in entries) entry.key: _normalizeJsonValue(entry.value),
  };
}

Object? _normalizeJsonValue(Object? value) {
  if (value is Map) {
    return _sortJsonObject(parsePlanMetadata(value));
  }
  if (value is Iterable) {
    return value.map(_normalizeJsonValue).toList();
  }
  return value;
}

/// Groups plan board rows by calendar day; undated items last.
List<({String? dayKey, List<PlanItemSummary> items})> groupPlanItemsByDay(
  List<PlanItemSummary> items,
) {
  final dated = <DateTime, List<PlanItemSummary>>{};
  final undated = <PlanItemSummary>[];

  for (final item in items) {
    final start = item.startsAt;
    if (start == null) {
      undated.add(item);
      continue;
    }
    final day = DateTime.utc(start.year, start.month, start.day);
    dated.putIfAbsent(day, () => []).add(item);
  }

  final sections = dated.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  final result = <({String? dayKey, List<PlanItemSummary> items})>[];
  for (final entry in sections) {
    final key = entry.key.toIso8601String().substring(0, 10);
    result.add((dayKey: key, items: entry.value));
  }
  if (undated.isNotEmpty) {
    result.add((dayKey: null, items: undated));
  }
  return result;
}

Map<String, List<TripListItemSummary>> groupListItemsByName(
  List<TripListItemSummary> items,
) {
  final grouped = <String, List<TripListItemSummary>>{};
  for (final item in items) {
    grouped.putIfAbsent(item.listName, () => []).add(item);
  }
  return grouped;
}
