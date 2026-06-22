import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'event_rsvp_models.dart';
import 'plan_models.dart';

final planRepositoryProvider = Provider<PlanRepository>((ref) {
  return PlanRepository(
    db: ref.watch(appDatabaseProvider),
    client: ref.watch(supabaseClientProvider),
    analytics: ref.watch(analyticsProvider),
    syncQueue: ref.watch(syncQueueProvider),
    syncWorker: ref.watch(syncWorkerProvider),
  );
});

class PlanRepository {
  PlanRepository({
    required AppDatabase db,
    required SupabaseClient client,
    required Analytics analytics,
    required SyncQueue syncQueue,
    required SyncWorker syncWorker,
    @visibleForTesting
    Future<void> Function(
      String functionName,
      Map<String, dynamic> params,
    )? rpcOverride,
    @visibleForTesting String? currentUserIdOverride,
  })  : _db = db,
        _client = client,
        _analytics = analytics,
        _syncQueue = syncQueue,
        _syncWorker = syncWorker,
        _rpcOverride = rpcOverride,
        _currentUserIdOverride = currentUserIdOverride;

  final AppDatabase _db;
  final SupabaseClient _client;
  final Analytics _analytics;
  final SyncQueue _syncQueue;
  final SyncWorker _syncWorker;
  final Future<void> Function(String functionName, Map<String, dynamic> params)?
      _rpcOverride;
  final String? _currentUserIdOverride;
  final _uuid = const Uuid();

  String? get _currentUserId =>
      _currentUserIdOverride ?? _client.auth.currentUser?.id;

  Future<void> _rpc(String functionName, Map<String, dynamic> params) async {
    final override = _rpcOverride;
    if (override != null) {
      await override(functionName, params);
      return;
    }
    await _client.rpc(functionName, params: params);
  }

  Stream<List<PlanItemSummary>> watchPlanItems(String tripId) {
    return _db.watchTripPlanItems(tripId).map(
          (rows) => rows.map(_toPlanSummary).toList(),
        );
  }

  Stream<List<TripListItemSummary>> watchListItems(String tripId) {
    return _db.watchTripListItems(tripId).map(
          (rows) => rows.map(_toListSummary).toList(),
        );
  }

  Stream<List<EventRsvpRow>> watchEventRsvps(String tripId) {
    return _db.watchTripPlanItemRsvps(tripId).map(
          (rows) => rows
              .map(
                (row) => EventRsvpRow(
                  id: row.id,
                  planItemId: row.planItemId,
                  userId: row.userId,
                  status: EventRsvpStatus.parse(row.status),
                  respondedAt: row.respondedAt,
                ),
              )
              .toList(),
        );
  }

  PlanItemSummary _toPlanSummary(LocalPlanItem row) => PlanItemSummary(
        id: row.id,
        tripId: row.tripId,
        kind: PlanItemKind.parse(row.kind),
        title: row.title,
        notes: row.notes,
        startsAt: row.startsAt,
        endsAt: row.endsAt,
        metadata: parsePlanMetadata(row.metadata),
        position: row.position,
      );

  TripListItemSummary _toListSummary(LocalTripListItem row) =>
      TripListItemSummary(
        id: row.id,
        tripId: row.tripId,
        listName: row.listName,
        label: row.label,
        checkedBy: row.checkedBy,
        checkedAt: row.checkedAt,
        position: row.position,
      );

  Future<int> _nextPlanPosition(String tripId) async {
    final rows = await (_db.select(_db.localPlanItems)
          ..where((p) => p.tripId.equals(tripId)))
        .get();
    if (rows.isEmpty) return 0;
    return rows.map((r) => r.position).reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<int> _nextListPosition(String tripId, String listName) async {
    final rows = await (_db.select(_db.localTripListItems)
          ..where((l) => l.tripId.equals(tripId))
          ..where((l) => l.listName.equals(listName)))
        .get();
    if (rows.isEmpty) return 0;
    return rows.map((r) => r.position).reduce((a, b) => a > b ? a : b) + 1;
  }

  Map<String, dynamic> _planPayload(Map<String, dynamic> row) => row;

  Future<String> addPlanItem(PlanItemInput input) async {
    final userId = _currentUserId;
    if (userId == null) throw StateError('Must be signed in');
    await _ensurePlanDatesWithinTrip(
      tripId: input.tripId,
      startsAt: input.startsAt,
      endsAt: input.endsAt,
    );

    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    final position = await _nextPlanPosition(input.tripId);
    final metadata = parsePlanMetadata(input.metadata);
    final payload = {
      'id': id,
      'trip_id': input.tripId,
      'kind': input.kind.name,
      'title': input.title.trim(),
      'notes': input.notes?.trim(),
      'starts_at': input.startsAt?.toUtc().toIso8601String(),
      'ends_at': input.endsAt?.toUtc().toIso8601String(),
      'metadata': metadata,
      'position': position,
      'created_by': userId,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    await _db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: Value(id),
        tripId: Value(input.tripId),
        kind: Value(input.kind.name),
        title: Value(input.title.trim()),
        notes: Value(input.notes?.trim()),
        startsAt: Value(input.startsAt?.toUtc()),
        endsAt: Value(input.endsAt?.toUtc()),
        metadata: Value(encodePlanMetadata(metadata)),
        position: Value(position),
        createdBy: Value(userId),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    await _syncQueue.enqueue(
      kind: SyncKind.planItemUpsert,
      payload: _planPayload(payload),
    );
    unawaited(_syncWorker.flush());

    _analytics.capture(
      VamoEvent.planItemCreated,
      properties: {
        'trip_id': input.tripId,
        'kind': input.kind.name,
        'has_dates': input.startsAt != null,
      },
    );

    return id;
  }

  Future<void> updatePlanItem({
    required String id,
    required PlanItemKind kind,
    required String title,
    String? notes,
    DateTime? startsAt,
    DateTime? endsAt,
    Map<String, Object?>? metadata,
  }) async {
    final existing = await (_db.select(_db.localPlanItems)
          ..where((p) => p.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) return;
    await _ensurePlanDatesWithinTrip(
      tripId: existing.tripId,
      startsAt: startsAt,
      endsAt: endsAt,
    );

    final now = DateTime.now().toUtc();
    final nextMetadata = parsePlanMetadata(metadata ?? existing.metadata);
    await _db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: Value(id),
        kind: Value(kind.name),
        title: Value(title.trim()),
        notes: Value(notes?.trim()),
        startsAt: Value(startsAt?.toUtc()),
        endsAt: Value(endsAt?.toUtc()),
        metadata: Value(encodePlanMetadata(nextMetadata)),
        updatedAt: Value(now),
      ),
    );

    final payload = {
      'id': id,
      'trip_id': existing.tripId,
      'kind': kind.name,
      'title': title.trim(),
      'notes': notes?.trim(),
      'starts_at': startsAt?.toUtc().toIso8601String(),
      'ends_at': endsAt?.toUtc().toIso8601String(),
      'metadata': nextMetadata,
      'position': existing.position,
      'created_by': existing.createdBy,
      'created_at': existing.createdAt.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    await _syncQueue.enqueue(
      kind: SyncKind.planItemUpsert,
      payload: _planPayload(payload),
    );
    unawaited(_syncWorker.flush());

    _analytics.capture(
      VamoEvent.planItemUpdated,
      properties: {'trip_id': existing.tripId, 'kind': kind.name},
    );
  }

  Future<void> deletePlanItem(String id) async {
    final existing = await (_db.select(_db.localPlanItems)
          ..where((p) => p.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) return;

    await _db.deletePlanItem(id);
    await _syncQueue.enqueue(
      kind: SyncKind.planItemDelete,
      payload: {'id': id},
    );
    unawaited(_syncWorker.flush());

    _analytics.capture(
      VamoEvent.planItemDeleted,
      properties: {'trip_id': existing.tripId, 'kind': existing.kind},
    );
  }

  Future<void> _ensurePlanDatesWithinTrip({
    required String tripId,
    required DateTime? startsAt,
    required DateTime? endsAt,
  }) async {
    final trip = await (_db.select(_db.localTrips)
          ..where((t) => t.id.equals(tripId)))
        .getSingleOrNull();
    final bounds = TripPlanDateBounds.fromIso(
      startDateIso: trip?.startDate,
      endDateIso: trip?.endDate,
    );
    final failure = validatePlanItemDates(
      startsAt: startsAt,
      endsAt: endsAt,
      bounds: bounds,
    );
    if (failure == PlanDateValidationFailure.endBeforeStart) {
      throw StateError('Plan item end date is before start date');
    }
    if (failure == PlanDateValidationFailure.outsideTripRange) {
      throw StateError('Plan item date is outside the trip date range');
    }
  }

  Future<void> reorderPlanItem({
    required String tripId,
    required String itemId,
    required int newPosition,
  }) async {
    final rows = await (_db.select(_db.localPlanItems)
          ..where((p) => p.tripId.equals(tripId)))
        .get();
    final moving = rows.where((r) => r.id == itemId).firstOrNull;
    if (moving == null) return;

    final other = rows.where((r) => r.position == newPosition).firstOrNull;
    final now = DateTime.now().toUtc();

    await _db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: Value(moving.id),
        position: Value(newPosition),
        updatedAt: Value(now),
      ),
    );
    if (other != null && other.id != moving.id) {
      await _db.upsertPlanItem(
        LocalPlanItemsCompanion(
          id: Value(other.id),
          position: Value(moving.position),
          updatedAt: Value(now),
        ),
      );
    }

    Future<void> enqueuePosition(LocalPlanItem row, int position) async {
      await _syncQueue.enqueue(
        kind: SyncKind.planItemUpsert,
        payload: {
          'id': row.id,
          'trip_id': row.tripId,
          'kind': row.kind,
          'title': row.title,
          'notes': row.notes,
          'starts_at': row.startsAt?.toUtc().toIso8601String(),
          'ends_at': row.endsAt?.toUtc().toIso8601String(),
          'metadata': parsePlanMetadata(row.metadata),
          'position': position,
          'created_by': row.createdBy,
          'created_at': row.createdAt.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
      );
    }

    await enqueuePosition(moving, newPosition);
    if (other != null) {
      await enqueuePosition(other, moving.position);
    }
    unawaited(_syncWorker.flush());
  }

  Future<String> addListItem({
    required String tripId,
    required String listName,
    required String label,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw StateError('Must be signed in');

    final trimmedList = listName.trim();
    final trimmedLabel = label.trim();
    if (trimmedList.isEmpty || trimmedLabel.isEmpty) {
      throw ArgumentError('list and label required');
    }

    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    final position = await _nextListPosition(tripId, trimmedList);

    await _db.upsertListItem(
      LocalTripListItemsCompanion(
        id: Value(id),
        tripId: Value(tripId),
        listName: Value(trimmedList),
        label: Value(trimmedLabel),
        position: Value(position),
        createdBy: Value(userId),
        createdAt: Value(now),
      ),
    );

    await _syncQueue.enqueue(
      kind: SyncKind.listItemUpsert,
      payload: {
        'id': id,
        'trip_id': tripId,
        'list_name': trimmedList,
        'label': trimmedLabel,
        'position': position,
        'created_by': userId,
        'created_at': now.toIso8601String(),
      },
    );
    unawaited(_syncWorker.flush());

    _analytics.capture(
      VamoEvent.listItemAdded,
      properties: {'trip_id': tripId},
    );

    return id;
  }

  Future<void> toggleListItem(String id) async {
    final userId = _currentUserId;
    if (userId == null) throw StateError('Must be signed in');

    final existing = await (_db.select(_db.localTripListItems)
          ..where((l) => l.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) return;

    final checking = existing.checkedBy == null;
    final now = DateTime.now().toUtc();

    await _db.upsertListItem(
      LocalTripListItemsCompanion(
        id: Value(id),
        checkedBy: checking ? Value(userId) : const Value(null),
        checkedAt: checking ? Value(now) : const Value(null),
      ),
    );

    await _syncQueue.enqueue(
      kind: SyncKind.listItemUpsert,
      payload: {
        'id': id,
        'trip_id': existing.tripId,
        'list_name': existing.listName,
        'label': existing.label,
        'position': existing.position,
        'created_by': existing.createdBy,
        'created_at': existing.createdAt.toIso8601String(),
        'checked_by': checking ? userId : null,
        'checked_at': checking ? now.toIso8601String() : null,
      },
    );
    unawaited(_syncWorker.flush());

    _analytics.capture(
      VamoEvent.listItemChecked,
      properties: {'trip_id': existing.tripId, 'checked': checking},
    );
  }

  Future<void> deleteListItem(String id) async {
    final existing = await (_db.select(_db.localTripListItems)
          ..where((l) => l.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) return;

    await _db.deleteListItem(id);
    await _syncQueue.enqueue(
      kind: SyncKind.listItemDelete,
      payload: {'id': id},
    );
    unawaited(_syncWorker.flush());
  }

  Future<void> setEventRsvp({
    required String planItemId,
    required EventRsvpStatus status,
  }) async {
    if (_currentUserId == null) {
      throw StateError('Must be signed in');
    }

    await _flushPendingPlanItem(planItemId);
    await _rpc('set_event_rsvp', {
      'p_plan_item_id': planItemId,
      'p_status': status.name,
    });
    _analytics.capture(
      VamoEvent.eventRsvp,
      properties: {'status': status.name},
    );

    final local = await (_db.select(_db.localPlanItems)
          ..where((p) => p.id.equals(planItemId)))
        .getSingleOrNull();
    if (local != null) {
      await syncPlanForTrips([local.tripId]);
    }
  }

  Future<void> clearEventRsvp({required String planItemId}) async {
    if (_currentUserId == null) {
      throw StateError('Must be signed in');
    }

    await _flushPendingPlanItem(planItemId);
    await _rpc('clear_event_rsvp', {
      'p_plan_item_id': planItemId,
    });
    _analytics.capture(
      VamoEvent.eventRsvp,
      properties: {'status': 'withdrawn'},
    );

    final local = await (_db.select(_db.localPlanItems)
          ..where((p) => p.id.equals(planItemId)))
        .getSingleOrNull();
    if (local != null) {
      await syncPlanForTrips([local.tripId]);
    }
  }

  Future<Map<PlanItemKind, PlanItemCapabilities>>
      fetchPlanItemCapabilities() async {
    final fallback = PlanItemCapabilities.fallbackByKind();
    if (_currentUserId == null) return fallback;

    try {
      final rows = await _client.from('plan_item_capabilities').select(
            'kind, wave_min, supports_rsvp, suggests_pois, has_live_status, '
            'has_check_times, sells_tickets, has_details_form',
          );
      final result = Map<PlanItemKind, PlanItemCapabilities>.from(fallback);
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final kind = PlanItemKind.parse(row['kind'] as String?);
        result[kind] = PlanItemCapabilities(
          kind: kind,
          waveMin: (row['wave_min'] as num?)?.toInt() ?? 2,
          supportsRsvp: row['supports_rsvp'] == true,
          suggestsPois: row['suggests_pois'] == true,
          hasLiveStatus: row['has_live_status'] == true,
          hasCheckTimes: row['has_check_times'] == true,
          sellsTickets: row['sells_tickets'] == true,
          hasDetailsForm: row['has_details_form'] == true,
        );
      }
      return result;
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'plan',
        action: 'fetch_item_capabilities',
        severity: ActionFailureSeverity.degraded,
        analytics: _analytics,
      );
      return fallback;
    }
  }

  Future<void> syncPlanForTrips(
    Iterable<String> tripIds, {
    Set<String> excludePlanIds = const {},
    Set<String> excludeListIds = const {},
  }) async {
    if (_currentUserId == null) return;
    final ids = tripIds.toList();
    if (ids.isEmpty) return;

    final planRows = await _client
        .from('trip_plan_items')
        .select(
          'id, trip_id, kind, title, notes, starts_at, ends_at, external_ref, '
          'attachment_path, metadata, position, created_by, updated_by, created_at, updated_at',
        )
        .inFilter('trip_id', ids);
    final localTrips =
        await (_db.select(_db.localTrips)..where((t) => t.id.isIn(ids))).get();
    final boundsByTrip = {
      for (final trip in localTrips)
        trip.id: TripPlanDateBounds.fromIso(
          startDateIso: trip.startDate,
          endDateIso: trip.endDate,
        ),
    };

    for (final row in (planRows as List).cast<Map<String, dynamic>>()) {
      final tripId = row['trip_id'] as String;
      final dates = normalizePlanItemDatesForTripRange(
        startsAt: _ts(row['starts_at']),
        endsAt: _ts(row['ends_at']),
        bounds: boundsByTrip[tripId] ?? const TripPlanDateBounds(),
      );
      await _db.upsertPlanItem(
        LocalPlanItemsCompanion(
          id: Value(row['id'] as String),
          tripId: Value(tripId),
          kind: Value(row['kind'] as String),
          title: Value(row['title'] as String),
          notes: Value(row['notes'] as String?),
          startsAt: Value(dates.startsAt),
          endsAt: Value(dates.endsAt),
          externalRef: Value(row['external_ref'] as String?),
          attachmentPath: Value(row['attachment_path'] as String?),
          metadata: Value(encodePlanMetadata(parsePlanMetadata(
            row['metadata'],
          ))),
          position: Value((row['position'] as num).toInt()),
          createdBy: Value(row['created_by'] as String),
          updatedBy: Value(row['updated_by'] as String?),
          createdAt: Value(DateTime.parse(row['created_at'] as String)),
          updatedAt: Value(DateTime.parse(row['updated_at'] as String)),
        ),
      );
    }

    final listRows = await _client
        .from('trip_list_items')
        .select(
          'id, trip_id, list_name, label, checked_by, checked_at, position, created_by, created_at',
        )
        .inFilter('trip_id', ids);

    for (final row in (listRows as List).cast<Map<String, dynamic>>()) {
      await _db.upsertListItem(
        LocalTripListItemsCompanion(
          id: Value(row['id'] as String),
          tripId: Value(row['trip_id'] as String),
          listName: Value(row['list_name'] as String),
          label: Value(row['label'] as String),
          checkedBy: Value(row['checked_by'] as String?),
          checkedAt: Value(_ts(row['checked_at'])),
          position: Value((row['position'] as num).toInt()),
          createdBy: Value(row['created_by'] as String),
          createdAt: Value(DateTime.parse(row['created_at'] as String)),
        ),
      );
    }

    final planIds = (planRows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => r['id'] as String)
        .toList();
    var rsvpRows = <dynamic>[];
    if (planIds.isNotEmpty) {
      rsvpRows = await _client
          .from('trip_plan_item_rsvps')
          .select('id, plan_item_id, user_id, status, responded_at')
          .inFilter('plan_item_id', planIds);

      for (final row in rsvpRows.cast<Map<String, dynamic>>()) {
        await _db.upsertPlanItemRsvp(
          LocalPlanItemRsvpsCompanion(
            id: Value(row['id'] as String),
            planItemId: Value(row['plan_item_id'] as String),
            userId: Value(row['user_id'] as String),
            status: Value(row['status'] as String),
            respondedAt: Value(DateTime.parse(row['responded_at'] as String)),
          ),
        );
      }
    }

    for (final tripId in ids) {
      final remotePlanIds = (planRows as List)
          .cast<Map<String, dynamic>>()
          .where((r) => r['trip_id'] == tripId)
          .map((r) => r['id'] as String)
          .toSet();
      final remoteListIds = (listRows as List)
          .cast<Map<String, dynamic>>()
          .where((r) => r['trip_id'] == tripId)
          .map((r) => r['id'] as String)
          .toSet();
      final remoteRsvpIds = planIds.isEmpty
          ? <String>{}
          : rsvpRows
              .cast<Map<String, dynamic>>()
              .where(
                (r) => remotePlanIds.contains(r['plan_item_id'] as String),
              )
              .map((r) => r['id'] as String)
              .toSet();
      await _db.prunePlanItemsForTrip(
        tripId,
        remotePlanIds,
        excludeIds: excludePlanIds,
      );
      await _db.pruneListItemsForTrip(
        tripId,
        remoteListIds,
        excludeIds: excludeListIds,
      );
      await _db.prunePlanItemRsvpsForTrip(tripId, remoteRsvpIds);
    }
  }

  DateTime? _ts(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value as String)?.toUtc();
  }

  Future<void> _flushPendingPlanItem(String planItemId) async {
    await _syncWorker.flush();
    final pending = await _syncQueue.collectPendingEntityIds();
    if (pending.planItemIds.contains(planItemId)) {
      throw StateError('Plan item is still syncing');
    }
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
