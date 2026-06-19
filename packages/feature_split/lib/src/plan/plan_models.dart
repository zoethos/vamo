import 'dart:convert';

import 'package:flutter/material.dart';

enum PlanItemKind {
  lodging,
  flight,
  train,
  activity,
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
        PlanItemKind.other => Icons.event_note_outlined,
      };
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
      suggestsPois: kind == PlanItemKind.activity,
      hasLiveStatus: kind == PlanItemKind.flight || kind == PlanItemKind.train,
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
