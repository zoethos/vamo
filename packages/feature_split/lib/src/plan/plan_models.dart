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

  PlanItemSummary copyWith({
    DateTime? startsAt,
    DateTime? endsAt,
    bool clearStartsAt = false,
    bool clearEndsAt = false,
  }) {
    return PlanItemSummary(
      id: id,
      tripId: tripId,
      kind: kind,
      title: title,
      notes: notes,
      startsAt: clearStartsAt ? null : startsAt ?? this.startsAt,
      endsAt: clearEndsAt ? null : endsAt ?? this.endsAt,
      metadata: metadata,
      position: position,
    );
  }
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
      supportsRsvp: kind == PlanItemKind.activity || kind == PlanItemKind.visit,
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
    return {for (final kind in PlanItemKind.values) kind: fallbackFor(kind)};
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

class TripPlanDateBounds {
  const TripPlanDateBounds({this.startDay, this.endDay});

  factory TripPlanDateBounds.fromIso({
    String? startDateIso,
    String? endDateIso,
  }) {
    final start = parsePlanIsoDay(startDateIso);
    final end = parsePlanIsoDay(endDateIso) ?? start;
    if (start != null && end != null && end.isBefore(start)) {
      return TripPlanDateBounds(startDay: start);
    }
    return TripPlanDateBounds(startDay: start, endDay: end);
  }

  final DateTime? startDay;
  final DateTime? endDay;

  bool get hasBounds => startDay != null || endDay != null;

  bool containsDateTime(DateTime? value) {
    if (value == null) return true;
    return containsDay(planDayForDateTime(value));
  }

  bool containsDay(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    final start = startDay;
    final end = endDay;
    if (start != null && normalized.isBefore(start)) return false;
    if (end != null && normalized.isAfter(end)) return false;
    return true;
  }
}

enum PlanDateValidationFailure { endBeforeStart, outsideTripRange }

DateTime? parsePlanIsoDay(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime planDayForDateTime(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

PlanDateValidationFailure? validatePlanItemDates({
  required DateTime? startsAt,
  required DateTime? endsAt,
  required TripPlanDateBounds bounds,
}) {
  if (startsAt != null && endsAt != null && endsAt.isBefore(startsAt)) {
    return PlanDateValidationFailure.endBeforeStart;
  }
  if (!bounds.containsDateTime(startsAt) || !bounds.containsDateTime(endsAt)) {
    return PlanDateValidationFailure.outsideTripRange;
  }
  return null;
}

({DateTime? startsAt, DateTime? endsAt}) normalizePlanItemDatesForTripRange({
  required DateTime? startsAt,
  required DateTime? endsAt,
  required TripPlanDateBounds bounds,
}) {
  final startValid = bounds.containsDateTime(startsAt);
  final endValid = bounds.containsDateTime(endsAt);
  if (!startValid) return (startsAt: null, endsAt: null);
  if (!endValid ||
      (startsAt != null && endsAt != null && endsAt.isBefore(startsAt))) {
    return (startsAt: startsAt, endsAt: null);
  }
  return (startsAt: startsAt, endsAt: endsAt);
}

PlanItemSummary normalizePlanItemSummaryForTripRange(
  PlanItemSummary item,
  TripPlanDateBounds bounds,
) {
  final dates = normalizePlanItemDatesForTripRange(
    startsAt: item.startsAt,
    endsAt: item.endsAt,
    bounds: bounds,
  );
  if (dates.startsAt == item.startsAt && dates.endsAt == item.endsAt) {
    return item;
  }
  return item.copyWith(
    startsAt: dates.startsAt,
    endsAt: dates.endsAt,
    clearStartsAt: dates.startsAt == null,
    clearEndsAt: dates.endsAt == null,
  );
}

class VisitPlaceMetadata {
  const VisitPlaceMetadata({
    required this.placeLabel,
    this.address,
    this.lat,
    this.lng,
    this.placeId,
    this.photoUrl,
    this.category,
    this.rating,
    this.price,
    this.website,
    this.phone,
    this.hours,
    this.about,
    this.aboutSource,
  });

  final String placeLabel;
  final String? address;
  final double? lat;
  final double? lng;
  final String? placeId;
  final String? photoUrl;
  final String? category;
  final double? rating;
  final int? price;
  final String? website;
  final String? phone;
  final String? hours;
  final String? about;
  final String? aboutSource;

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
    photoUrl: _stringValue(metadata['photo_url']) ??
        _stringValue(metadata['image_url']) ??
        _stringValue(metadata['thumbnail_url']),
    category: _stringValue(metadata['category']),
    rating: _doubleValue(metadata['rating']),
    price: _intValue(metadata['price']),
    website: _stringValue(metadata['website']),
    phone: _stringValue(metadata['phone']),
    hours: _stringValue(metadata['hours']),
    about: _stringValue(metadata['about']),
    aboutSource: _stringValue(metadata['about_source']),
  );
}

Map<String, Object?> buildVisitPlaceMetadata({
  required String placeLabel,
  String? address,
  double? lat,
  double? lng,
  String? placeId,
  String? photoUrl,
  String? category,
  double? rating,
  int? price,
  String? website,
  String? phone,
  String? hours,
  String? about,
  String? aboutSource,
}) {
  final normalizedLabel = placeLabel.trim();
  final normalizedAddress = address?.trim();
  final normalizedPlaceId = placeId?.trim();
  final normalizedPhotoUrl = photoUrl?.trim();
  final normalizedCategory = category?.trim();
  final normalizedWebsite = website?.trim();
  final normalizedPhone = phone?.trim();
  final normalizedHours = hours?.trim();
  final normalizedAbout = about?.trim();
  final normalizedAboutSource = aboutSource?.trim();
  return <String, Object?>{
    'place_label': normalizedLabel,
    if (normalizedAddress != null && normalizedAddress.isNotEmpty)
      'address': normalizedAddress,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    if (normalizedPlaceId != null && normalizedPlaceId.isNotEmpty)
      'place_id': normalizedPlaceId,
    if (normalizedPhotoUrl != null && normalizedPhotoUrl.isNotEmpty)
      'photo_url': normalizedPhotoUrl,
    if (normalizedCategory != null && normalizedCategory.isNotEmpty)
      'category': normalizedCategory,
    if (rating != null) 'rating': rating,
    if (price != null) 'price': price,
    if (normalizedWebsite != null && normalizedWebsite.isNotEmpty)
      'website': normalizedWebsite,
    if (normalizedPhone != null && normalizedPhone.isNotEmpty)
      'phone': normalizedPhone,
    if (normalizedHours != null && normalizedHours.isNotEmpty)
      'hours': normalizedHours,
    if (normalizedAbout != null && normalizedAbout.isNotEmpty)
      'about': normalizedAbout,
    if (normalizedAboutSource != null && normalizedAboutSource.isNotEmpty)
      'about_source': normalizedAboutSource,
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

int? _intValue(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
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
    {TripPlanDateBounds bounds = const TripPlanDateBounds()}) {
  final dated = <DateTime, List<PlanItemSummary>>{};
  final undated = <PlanItemSummary>[];

  for (final rawItem in items) {
    final item = normalizePlanItemSummaryForTripRange(rawItem, bounds);
    final start = item.startsAt;
    if (start == null) {
      undated.add(item);
      continue;
    }
    final local = start.toLocal();
    final day = DateTime.utc(local.year, local.month, local.day);
    dated.putIfAbsent(day, () => []).add(item);
  }

  final sections = dated.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  final result = <({String? dayKey, List<PlanItemSummary> items})>[];
  for (final entry in sections) {
    entry.value.sort(_comparePlanItemsForTimeline);
    final key = entry.key.toIso8601String().substring(0, 10);
    result.add((dayKey: key, items: entry.value));
  }
  if (undated.isNotEmpty) {
    undated.sort(_comparePlanItemsForTimeline);
    result.add((dayKey: null, items: undated));
  }
  return result;
}

int _comparePlanItemsForTimeline(PlanItemSummary a, PlanItemSummary b) {
  final aStart = a.startsAt;
  final bStart = b.startsAt;
  if (aStart == null && bStart != null) return 1;
  if (aStart != null && bStart == null) return -1;
  if (aStart != null && bStart != null) {
    final time = aStart.compareTo(bStart);
    if (time != 0) return time;
  }
  return a.position.compareTo(b.position);
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
