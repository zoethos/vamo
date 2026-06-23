import 'package:flutter/foundation.dart';

import '../plan/plan_models.dart';

/// A single AI-drafted stop, ready to become a [PlanItemInput] on accept.
@immutable
class RouteDraftItem {
  const RouteDraftItem({
    required this.kind,
    required this.title,
    this.startsAt,
    this.endsAt,
    this.transferSubtype,
    this.legIndex,
    this.notes,
  });

  final PlanItemKind kind;
  final String title;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final TransferSubtype? transferSubtype;
  final int? legIndex;
  final String? notes;

  static RouteDraftItem? fromJson(Map<dynamic, dynamic> json) {
    final kindRaw = json['kind'];
    final titleRaw = json['title'];
    if (kindRaw is! String) return null;
    if (titleRaw is! String || titleRaw.trim().isEmpty) return null;
    final subtypeRaw = json['transfer_subtype'];
    final notesRaw = json['notes'];
    final legRaw = json['leg_index'];
    return RouteDraftItem(
      kind: PlanItemKind.parse(kindRaw),
      title: titleRaw.trim(),
      startsAt: _parseDate(json['starts_at']),
      endsAt: _parseDate(json['ends_at']),
      transferSubtype:
          subtypeRaw is String ? TransferSubtype.parse(subtypeRaw) : null,
      legIndex: legRaw is int ? legRaw : null,
      notes: notesRaw is String && notesRaw.trim().isNotEmpty
          ? notesRaw.trim()
          : null,
    );
  }

  /// Maps the drafted stop to a Plan create input; transfer stops carry their
  /// subtype as metadata so they render with the right type accent.
  PlanItemInput toPlanItemInput(String tripId) {
    final metadata = kind == PlanItemKind.transfer && transferSubtype != null
        ? buildTransferMetadata(subtype: transferSubtype!)
        : const <String, Object?>{};
    return PlanItemInput(
      tripId: tripId,
      kind: kind,
      title: title,
      notes: notes,
      startsAt: startsAt,
      endsAt: endsAt,
      metadata: metadata,
    );
  }
}

/// A drafted route returned by the `draft-trip-route` Edge Function.
@immutable
class RouteDraft {
  const RouteDraft({
    required this.draftId,
    required this.items,
    required this.warnings,
    required this.unresolvedQuestions,
  });

  final String draftId;
  final List<RouteDraftItem> items;
  final List<String> warnings;
  final List<String> unresolvedQuestions;

  bool get isEmpty => items.isEmpty;

  /// Parses the function payload (`{ ok, draft: { draft_id, plan_items, ... } }`).
  static RouteDraft? fromPayload(Object? data) {
    if (data is! Map) return null;
    final draft = data['draft'];
    if (draft is! Map) return null;
    final itemsRaw = draft['plan_items'];
    if (itemsRaw is! List) return null;
    final items = <RouteDraftItem>[];
    for (final raw in itemsRaw) {
      if (raw is Map) {
        final item = RouteDraftItem.fromJson(raw);
        if (item != null) items.add(item);
      }
    }
    return RouteDraft(
      draftId: draft['draft_id'] is String ? draft['draft_id'] as String : '',
      items: items,
      warnings: _stringList(draft['warnings']),
      unresolvedQuestions: _stringList(draft['unresolved_questions']),
    );
  }
}

DateTime? _parseDate(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse('${raw}T00:00:00');
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final v in raw)
      if (v is String && v.trim().isNotEmpty) v.trim(),
  ];
}
