import 'dart:convert';

import 'package:drift/drift.dart';

import '../analytics/action_failure.dart';
import '../db/app_database.dart';
import '../sync/sync_operation.dart';
import '../sync/sync_queue.dart';
import 'offline_pack_models.dart';

enum OfflinePackRefreshTrigger {
  tripEdit,
  appForeground,
  preDeparture,
}

class TripOfflinePackService {
  TripOfflinePackService({
    required AppDatabase db,
    required SyncQueue syncQueue,
    OfflinePackPolicy policy = const OfflinePackPolicy(),
    DateTime Function()? now,
  })  : _db = db,
        _syncQueue = syncQueue,
        _policy = policy,
        _now = now ?? (() => DateTime.now().toUtc());

  final AppDatabase _db;
  final SyncQueue _syncQueue;
  final OfflinePackPolicy _policy;
  final DateTime Function() _now;

  Future<OfflinePackManifest> refreshEssentials(String tripId) async {
    final now = _now();
    final previous = await _db.getOfflinePack(
      tripId,
      OfflinePackTier.essentials.value,
    );
    final counts = await _rowCounts(tripId);
    final pendingOutboxCount = await _pendingOutboxCountForTrip(tripId);
    final manifest = _policy.evaluateEssentials(
      tripId: tripId,
      counts: counts,
      pendingOutboxCount: pendingOutboxCount,
      now: now,
      previousLastUpdatedAt: previous?.lastUpdatedAt?.toUtc(),
      previousEvictionPinned: previous?.evictionPinned ?? false,
      previousSecureSnapshotRef: previous?.secureSnapshotRef,
    );
    await _db.upsertOfflinePack(_toCompanion(manifest, now));
    return manifest;
  }

  Future<OfflinePackManifest?> getEssentialsManifest(String tripId) async {
    final row = await _db.getOfflinePack(
      tripId,
      OfflinePackTier.essentials.value,
    );
    if (row == null) return null;
    return _fromRow(row);
  }

  Future<OfflinePackManifest?> refreshEssentialsIfNeeded(
    String tripId, {
    required OfflinePackRefreshTrigger trigger,
  }) async {
    final current = await getEssentialsManifest(tripId);
    final trip = await _db.watchTrip(tripId).first;
    if (trip == null) return current;
    if (!_policy.shouldRefresh(
      trigger: trigger,
      manifest: current,
      now: _now(),
      tripStartDate: _parseDate(trip.startDate),
    )) {
      return current;
    }
    return refreshEssentials(tripId);
  }

  Future<List<OfflinePackManifest>> refreshDueLocalEssentials({
    required OfflinePackRefreshTrigger trigger,
  }) async {
    final trips = await _db.watchAllTrips().first;
    final manifests = <OfflinePackManifest>[];
    for (final trip in trips.where(_tracksOfflineEssentials)) {
      final refreshed = await refreshEssentialsIfNeeded(
        trip.id,
        trigger: trigger,
      );
      if (refreshed != null) manifests.add(refreshed);
    }
    return manifests;
  }

  Future<void> markEssentialsAccessed(String tripId) async {
    await _db.updateOfflinePackFields(
      tripId,
      OfflinePackTier.essentials.value,
      LocalOfflinePacksCompanion(lastAccessedAt: Value(_now())),
    );
  }

  Future<List<String>> evictEssentials({
    required int maxWarmPacks,
    bool storagePressure = false,
  }) async {
    final rows = await _db.listOfflinePacks();
    final trips = {
      for (final trip in await _db.watchAllTrips().first) trip.id: trip,
    };
    final candidates = rows
        .where((row) => row.tier == OfflinePackTier.essentials.value)
        .map(
          (row) => OfflinePackEvictionCandidate(
            tripId: row.tripId,
            tier: OfflinePackTier.parse(row.tier),
            status: OfflinePackStatus.parse(row.status),
            lastAccessedAt: row.lastAccessedAt?.toUtc(),
            tripEndDate: _parseDate(trips[row.tripId]?.endDate),
            lifecycle: trips[row.tripId]?.lifecycle ?? 'deleted',
            evictionPinned: row.evictionPinned,
            pendingOutboxCount: row.pendingOutboxCount,
            storageBytes: row.storageBytes,
          ),
        )
        .toList(growable: false);
    final plan = _policy.planEviction(
      candidates: candidates,
      maxWarmPacks: maxWarmPacks,
      now: _now(),
      storagePressure: storagePressure,
    );
    for (final tripId in plan.evictTripIds) {
      await _db.deleteOfflinePack(tripId, OfflinePackTier.essentials.value);
    }
    return plan.evictTripIds;
  }

  Future<OfflinePackRowCounts> _rowCounts(String tripId) async {
    final trip = await (_db.select(_db.localTrips)
          ..where((t) => t.id.equals(tripId)))
        .getSingleOrNull();
    final members = await (_db.select(_db.localTripMembers)
          ..where((m) => m.tripId.equals(tripId)))
        .get();
    final planItems = await (_db.select(_db.localPlanItems)
          ..where((p) => p.tripId.equals(tripId)))
        .get();
    final checklists = await (_db.select(_db.localTripListItems)
          ..where((l) => l.tripId.equals(tripId)))
        .get();
    final places = await (_db.select(_db.localPlaces)
          ..where((p) => p.tripId.equals(tripId)))
        .get();
    final fxRates = await (_db.select(_db.localTripFxRates)
          ..where((r) => r.tripId.equals(tripId)))
        .get();
    final expenses = await (_db.select(_db.localExpenses)
          ..where((e) => e.tripId.equals(tripId)))
        .get();
    final settlements = await (_db.select(_db.localSettlements)
          ..where((s) => s.tripId.equals(tripId)))
        .get();
    final rsvps = await (_db.select(_db.localPlanItemRsvps)
          ..where(
            (r) => r.planItemId.isInQuery(
              _db.selectOnly(_db.localPlanItems)
                ..addColumns([_db.localPlanItems.id])
                ..where(_db.localPlanItems.tripId.equals(tripId)),
            ),
          ))
        .get();
    final shares = await (_db.select(_db.localExpenseShares)
          ..where(
            (s) => s.expenseId.isInQuery(
              _db.selectOnly(_db.localExpenses)
                ..addColumns([_db.localExpenses.id])
                ..where(_db.localExpenses.tripId.equals(tripId)),
            ),
          ))
        .get();

    return OfflinePackRowCounts(
      trips: trip == null ? 0 : 1,
      members: members.length,
      planItems: planItems.length,
      checklists: checklists.length,
      rsvps: rsvps.length,
      places: places.length,
      fxRates: fxRates.length,
      expenses: expenses.length,
      expenseShares: shares.length,
      settlements: settlements.length,
    );
  }

  Future<int> _pendingOutboxCountForTrip(String tripId) async {
    final rows = await _syncQueue.pending(limit: 500);
    return rows.where((row) {
      try {
        return _payloadReferencesTrip(decodePayload(row.payload), tripId);
      } catch (error, stackTrace) {
        reportAndLog(
          error,
          stackTrace,
          screen: 'offline_pack',
          action: 'decode_outbox_payload',
          severity: ActionFailureSeverity.degraded,
        );
        return false;
      }
    }).length;
  }
}

class OfflinePackPolicy {
  const OfflinePackPolicy({
    this.staleAfter = const Duration(hours: 24),
    this.preDepartureWindow = const Duration(hours: 48),
  });

  final Duration staleAfter;
  final Duration preDepartureWindow;

  OfflinePackManifest evaluateEssentials({
    required String tripId,
    required OfflinePackRowCounts counts,
    required int pendingOutboxCount,
    required DateTime now,
    DateTime? previousLastUpdatedAt,
    bool previousEvictionPinned = false,
    String? previousSecureSnapshotRef,
    String? lastError,
    bool syncing = false,
  }) {
    final missing = <OfflinePackScope>[
      if (counts.trips == 0) OfflinePackScope.trip,
      if (counts.members == 0) OfflinePackScope.members,
    ];
    final staleReasons = <String>[
      if (pendingOutboxCount > 0) 'pending_outbox',
    ];
    final updatedAt = counts.trips == 0 ? previousLastUpdatedAt : now;
    final status = syncing
        ? OfflinePackStatus.syncing
        : lastError != null
            ? OfflinePackStatus.failed
            : missing.contains(OfflinePackScope.trip)
                ? OfflinePackStatus.failed
                : missing.isNotEmpty || pendingOutboxCount > 0
                    ? OfflinePackStatus.partial
                    : OfflinePackStatus.ready;

    return OfflinePackManifest(
      tripId: tripId,
      tier: OfflinePackTier.essentials,
      status: status,
      lastUpdatedAt: updatedAt,
      rowCounts: counts,
      missingScopes: missing,
      staleReasons: staleReasons,
      pendingOutboxCount: pendingOutboxCount,
      storageBytes: 0,
      secureSnapshotRef: previousSecureSnapshotRef,
      lastError: lastError,
      evictionPinned: previousEvictionPinned,
      lastAccessedAt: now,
    );
  }

  OfflinePackManifest surfaceStaleness({
    required OfflinePackManifest manifest,
    required DateTime now,
  }) {
    final updatedAt = manifest.lastUpdatedAt;
    if (updatedAt == null ||
        manifest.status == OfflinePackStatus.failed ||
        manifest.status == OfflinePackStatus.partial ||
        now.difference(updatedAt.toUtc()) <= staleAfter) {
      return manifest;
    }
    return manifest.copyWith(
      status: OfflinePackStatus.stale,
      staleReasons: {
        ...manifest.staleReasons,
        'last_updated_age',
      }.toList(growable: false),
    );
  }

  bool shouldRefresh({
    required OfflinePackRefreshTrigger trigger,
    required OfflinePackManifest? manifest,
    required DateTime now,
    DateTime? tripStartDate,
  }) {
    if (manifest == null) return true;
    switch (trigger) {
      case OfflinePackRefreshTrigger.tripEdit:
        return true;
      case OfflinePackRefreshTrigger.appForeground:
        final updatedAt = manifest.lastUpdatedAt;
        return manifest.status == OfflinePackStatus.partial ||
            manifest.status == OfflinePackStatus.failed ||
            updatedAt == null ||
            now.difference(updatedAt.toUtc()) > staleAfter;
      case OfflinePackRefreshTrigger.preDeparture:
        if (tripStartDate == null) return false;
        final untilStart = tripStartDate.difference(now);
        if (untilStart.isNegative || untilStart > preDepartureWindow) {
          return false;
        }
        final updatedAt = manifest.lastUpdatedAt;
        return updatedAt == null ||
            now.difference(updatedAt.toUtc()) > const Duration(hours: 6);
    }
  }

  OfflinePackEvictionPlan planEviction({
    required List<OfflinePackEvictionCandidate> candidates,
    required int maxWarmPacks,
    required DateTime now,
    bool storagePressure = false,
  }) {
    final evictable = candidates
        .where((candidate) => !candidate.isProtected)
        .toList(growable: false);
    final pastOrArchived = evictable
        .where((candidate) => candidate.isPastOrArchived(now))
        .toList(growable: false)
      ..sort(_oldestAccessFirst);
    final remaining = evictable
        .where((candidate) => !candidate.isPastOrArchived(now))
        .toList(growable: false)
      ..sort(_oldestAccessFirst);

    final activeWarmLimit = storagePressure ? 0 : maxWarmPacks;
    final allowedRemaining = activeWarmLimit.clamp(0, 1 << 20);
    final overCap = remaining.length > allowedRemaining
        ? remaining.take(remaining.length - allowedRemaining)
        : const Iterable<OfflinePackEvictionCandidate>.empty();

    return OfflinePackEvictionPlan(
      evictTripIds: [
        ...pastOrArchived.map((candidate) => candidate.tripId),
        ...overCap.map((candidate) => candidate.tripId),
      ],
    );
  }

  OfflinePackMapSnapshotPlan mapSnapshotPlan({String provider = 'osm'}) {
    return const OfflinePackMapSnapshotPlan(
      pinsOnly: true,
      bulkTilePrefetch: false,
      tileDownloadRequests: 0,
      licenseGuard: 'pins_list_only_no_bulk_tile_prefetch',
    );
  }
}

LocalOfflinePacksCompanion _toCompanion(
  OfflinePackManifest manifest,
  DateTime now,
) {
  return LocalOfflinePacksCompanion.insert(
    tripId: manifest.tripId,
    tier: manifest.tier.value,
    status: manifest.status.value,
    createdAt: now,
    updatedAt: now,
    lastUpdatedAt: Value(manifest.lastUpdatedAt),
    rowCountsJson: Value(jsonEncode(manifest.rowCounts.toJson())),
    missingScopesJson: Value(
      jsonEncode(manifest.missingScopes.map((scope) => scope.value).toList()),
    ),
    staleReasonsJson: Value(jsonEncode(manifest.staleReasons)),
    pendingOutboxCount: Value(manifest.pendingOutboxCount),
    storageBytes: Value(manifest.storageBytes),
    secureSnapshotRef: Value(manifest.secureSnapshotRef),
    lastError: Value(manifest.lastError),
    evictionPinned: Value(manifest.evictionPinned),
    lastAccessedAt: Value(manifest.lastAccessedAt),
  );
}

OfflinePackManifest _fromRow(LocalOfflinePack row) {
  return OfflinePackManifest(
    tripId: row.tripId,
    tier: OfflinePackTier.parse(row.tier),
    status: OfflinePackStatus.parse(row.status),
    lastUpdatedAt: row.lastUpdatedAt?.toUtc(),
    rowCounts: OfflinePackRowCounts.fromJson(_jsonMap(row.rowCountsJson)),
    missingScopes: _jsonList(row.missingScopesJson)
        .map(_scopeFromValue)
        .whereType<OfflinePackScope>()
        .toList(growable: false),
    staleReasons: _jsonList(row.staleReasonsJson).cast<String>(),
    pendingOutboxCount: row.pendingOutboxCount,
    storageBytes: row.storageBytes,
    secureSnapshotRef: row.secureSnapshotRef,
    lastError: row.lastError,
    evictionPinned: row.evictionPinned,
    lastAccessedAt: row.lastAccessedAt?.toUtc(),
  );
}

bool _payloadReferencesTrip(Object? value, String tripId) {
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key == 'trip_id' && entry.value == tripId) return true;
      if (_payloadReferencesTrip(entry.value, tripId)) return true;
    }
  }
  if (value is Iterable) {
    return value.any((entry) => _payloadReferencesTrip(entry, tripId));
  }
  return false;
}

Map<String, Object?> _jsonMap(String value) {
  final decoded = jsonDecode(value);
  if (decoded is Map<String, Object?>) return decoded;
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry('$key', value));
  }
  return const {};
}

List<Object?> _jsonList(String value) {
  final decoded = jsonDecode(value);
  return decoded is List ? decoded : const [];
}

OfflinePackScope? _scopeFromValue(Object? value) {
  for (final scope in OfflinePackScope.values) {
    if (scope.value == value) return scope;
  }
  return null;
}

DateTime? _parseDate(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

bool _tracksOfflineEssentials(LocalTrip trip) {
  return switch (trip.lifecycle) {
    'cancelled' || 'closed' => false,
    _ => true,
  };
}

int _oldestAccessFirst(
  OfflinePackEvictionCandidate a,
  OfflinePackEvictionCandidate b,
) {
  final aTime = a.lastAccessedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bTime = b.lastAccessedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return aTime.compareTo(bTime);
}
