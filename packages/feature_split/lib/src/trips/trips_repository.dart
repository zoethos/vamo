import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../capture/capture_repository.dart';
import '../capture/capture_storage.dart';
import '../expenses/expenses_repository.dart';
import '../places/places_repository.dart';
import '../settle/settlements_repository.dart';
import 'trips_models.dart';

final tripsRepositoryProvider = Provider<TripsRepository>((ref) {
  return TripsRepository(
    db: ref.watch(appDatabaseProvider),
    client: ref.watch(supabaseClientProvider),
    analytics: ref.watch(analyticsProvider),
    expenses: ref.watch(expensesRepositoryProvider),
    settlements: ref.watch(settlementsRepositoryProvider),
    capture: ref.watch(captureRepositoryProvider),
    places: ref.watch(placesRepositoryProvider),
    syncQueue: ref.watch(syncQueueProvider),
  );
});

/// Slice 1: Drift is the UI source of truth; Supabase is written on create and
/// pulled on sync; outbox push via Slice 9 [SyncWorker].
class TripsRepository {
  TripsRepository({
    required AppDatabase db,
    required SupabaseClient client,
    required Analytics analytics,
    required ExpensesRepository expenses,
    required SettlementsRepository settlements,
    required CaptureRepository capture,
    required PlacesRepository places,
    required SyncQueue syncQueue,
  })  : _db = db,
        _client = client,
        _analytics = analytics,
        _expenses = expenses,
        _settlements = settlements,
        _capture = capture,
        _places = places,
        _syncQueue = syncQueue;

  final AppDatabase _db;
  final SupabaseClient _client;
  final Analytics _analytics;
  final ExpensesRepository _expenses;
  final SettlementsRepository _settlements;
  final CaptureRepository _capture;
  final PlacesRepository _places;
  final SyncQueue _syncQueue;
  final _uuid = const Uuid();

  Stream<List<TripSummary>> watchTripSummaries() {
    return _db.watchAllTrips().map(
          (rows) => rows
              .map(
                (r) => TripSummary(
                  id: r.id,
                  name: r.name,
                  destination: r.destination,
                  startDate: r.startDate,
                  endDate: r.endDate,
                  baseCurrency: r.baseCurrency,
                  lifecycle: r.lifecycle,
                ),
              )
              .toList(),
        );
  }

  Stream<TripDetail?> watchTrip(String id) {
    return _db.watchTrip(id).map((row) {
      if (row == null) return null;
      return TripDetail(
        id: row.id,
        name: row.name,
        destination: row.destination,
        startDate: row.startDate,
        endDate: row.endDate,
        baseCurrency: row.baseCurrency,
        ownerId: row.ownerId,
        lifecycle: row.lifecycle,
        closeRequestedAt: row.closeRequestedAt,
      );
    });
  }

  Stream<LocalTripMember?> watchMember(String tripId, String userId) {
    return _db.watchMember(tripId, userId);
  }

  Stream<bool> watchTripHasCloseObjection(String tripId) {
    return _db.watchActiveMembers(tripId).map(
          (members) => members.any((m) => m.closeObjectedAt != null),
        );
  }

  Stream<int> watchActiveMemberCount(String tripId) =>
      _db.watchActiveMemberCount(tripId);

  /// Pulls remote trips + membership into Drift. Call after sign-in and on list refresh.

  /// Wipes all cached trip data on sign-out (trips, members, expenses, shares) so the
  /// next account never sees the previous user's private cache.
  Future<void> clearLocal() async {
    await CaptureStorage.clearAll();
    await _db.delete(_db.localSyncOutbox).go();
    await _db.delete(_db.localTripPhotos).go();
    await _db.delete(_db.localTripNotes).go();
    await _db.delete(_db.localSettlements).go();
    await _db.delete(_db.localExpenseShares).go();
    await _db.delete(_db.localExpenses).go();
    await _db.delete(_db.localTripMembers).go();
    await _db.delete(_db.localPlaces).go();
    await _db.delete(_db.localTrips).go();
  }

  /// Pulls one trip's remote data into Drift (realtime refresh).
  Future<void> syncTripFromRemote(String tripId) async {
    if (_client.auth.currentUser?.id == null) return;
    final pending = await _syncQueue.collectPendingEntityIds();
    await _pullTripsAndMembers(remoteTripIds: {tripId}, onlyTripId: tripId);
    await _places.syncPlacesForTrips([tripId]);
    await _expenses.syncExpensesForTrips(
      [tripId],
      excludeExpenseIds: pending.expenseIds,
    );
    await _settlements.syncSettlementsForTrips(
      [tripId],
      excludeSettlementIds: pending.settlementIds,
    );
    await _capture.syncCaptureForTrips([tripId]);
  }

  Future<void> syncFromRemote() async {
    if (_client.auth.currentUser?.id == null) return;

    final tripRows = await _client
        .from('trips')
        .select(_tripSelectFields)
        .order('created_at', ascending: false);

    final remoteIds = (tripRows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => r['id'] as String)
        .toSet();

    await _pullTripsAndMembers(remoteTripIds: remoteIds);

    await _pruneLocalTrips(remoteIds);

    final pending = await _syncQueue.collectPendingEntityIds();
    await _places.syncPlacesForTrips(remoteIds);
    await _expenses.syncExpensesForTrips(
      remoteIds,
      excludeExpenseIds: pending.expenseIds,
    );
    await _settlements.syncSettlementsForTrips(
      remoteIds,
      excludeSettlementIds: pending.settlementIds,
    );
    await _capture.syncCaptureForTrips(remoteIds);
  }

  Future<void> _pullTripsAndMembers({
    required Set<String> remoteTripIds,
    String? onlyTripId,
  }) async {
    final tripRows = onlyTripId == null
        ? await _client
            .from('trips')
            .select(_tripSelectFields)
            .order('created_at', ascending: false)
        : await _client
            .from('trips')
            .select(_tripSelectFields)
            .eq('id', onlyTripId);

    final memberQuery = _client.from('trip_members').select(
          'trip_id, user_id, role, status, completed_at, close_accepted_at, '
          'close_objected_at, close_objection_reason, profiles(display_name)',
        );
    final memberRows = onlyTripId == null
        ? await memberQuery
        : await memberQuery.eq('trip_id', onlyTripId);

    final now = DateTime.now().toUtc();
    for (final row in (tripRows as List).cast<Map<String, dynamic>>()) {
      final id = row['id'] as String;
      if (!remoteTripIds.contains(id)) continue;
      final created = DateTime.parse(row['created_at'] as String);
      await _db.upsertTrip(
        LocalTripsCompanion(
          id: Value(id),
          name: Value(row['name'] as String),
          destination: Value(row['destination'] as String?),
          startDate: Value(_dateToIso(row['start_date'])),
          endDate: Value(_dateToIso(row['end_date'])),
          ownerId: Value(row['owner_id'] as String),
          baseCurrency: Value(row['base_currency'] as String),
          lifecycle: Value((row['lifecycle'] as String?) ?? 'active'),
          closeRequestedAt: Value(
            _timestamp(row['close_requested_at']),
          ),
          createdAt: Value(created),
          updatedAt: Value(now),
        ),
      );
    }

    for (final row in (memberRows as List).cast<Map<String, dynamic>>()) {
      final tripId = row['trip_id'] as String;
      if (!remoteTripIds.contains(tripId)) continue;
      final profile = row['profiles'] as Map<String, dynamic>?;
      await _db.upsertMember(
        LocalTripMembersCompanion(
          tripId: Value(tripId),
          userId: Value(row['user_id'] as String),
          role: Value(row['role'] as String),
          status: Value(row['status'] as String),
          displayName: Value(profile?['display_name'] as String?),
          completedAt: Value(_timestamp(row['completed_at'])),
          closeAcceptedAt: Value(_timestamp(row['close_accepted_at'])),
          closeObjectedAt: Value(_timestamp(row['close_objected_at'])),
          closeObjectionReason: Value(
            row['close_objection_reason'] as String?,
          ),
        ),
      );
    }
  }

  Future<void> _pruneLocalTrips(Set<String> remoteTripIds) async {
    final local = await _db.select(_db.localTrips).get();
    for (final trip in local) {
      if (!remoteTripIds.contains(trip.id)) {
        await _db.deleteTripCascade(trip.id);
      }
    }
  }

  Future<String> createTrip(CreateTripInput input) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be signed in to create a trip');
    }

    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    await _db.upsertTrip(
      LocalTripsCompanion(
        id: Value(id),
        name: Value(input.name.trim()),
        destination: Value(input.destination?.trim()),
        startDate: Value(input.startDate),
        endDate: Value(input.endDate),
        ownerId: Value(userId),
        baseCurrency: Value(input.baseCurrency),
        lifecycle: const Value('active'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await _db.upsertMember(
      LocalTripMembersCompanion(
        tripId: Value(id),
        userId: Value(userId),
        role: const Value('owner'),
        status: const Value('active'),
      ),
    );

    try {
      await _client.rpc(
        'create_trip',
        params: {
          'p_id': id,
          'p_name': input.name.trim(),
          'p_destination': input.destination?.trim(),
          'p_start_date': input.startDate,
          'p_end_date': input.endDate,
          'p_base_currency': input.baseCurrency,
        },
      );
    } catch (e) {
      await (_db.delete(_db.localTrips)..where((t) => t.id.equals(id))).go();
      await (_db.delete(_db.localTripMembers)
            ..where((m) => m.tripId.equals(id)))
          .go();
      rethrow;
    }

    _analytics.capture(
      VamoEvent.tripCreated,
      properties: {
        'trip_id': id,
        'base_currency': input.baseCurrency,
        'solo': true,
      },
    );

    return id;
  }

  /// Owner-only: grant or revoke co-admin (RPC `set_member_role`).
  Future<void> setMemberRole({
    required String tripId,
    required String userId,
    required String role,
  }) async {
    await _client.rpc('set_member_role', params: {
      'p_trip_id': tripId,
      'p_user_id': userId,
      'p_role': role,
    });
    await syncTripFromRemote(tripId);
  }

  Future<void> requestTripClose(String tripId) async {
    await _client.rpc('request_trip_close', params: {'p_trip_id': tripId});
    await syncTripFromRemote(tripId);
    _analytics.capture(
      VamoEvent.closeRequested,
      properties: {'trip_id': tripId},
    );
  }

  Future<void> markTripMemberComplete(String tripId) async {
    await _client.rpc(
      'mark_trip_member_complete',
      params: {'p_trip_id': tripId},
    );
    await syncTripFromRemote(tripId);
  }

  Future<void> acceptTripClose(String tripId) async {
    await _client.rpc('accept_trip_close', params: {'p_trip_id': tripId});
    await syncTripFromRemote(tripId);
    _analytics.capture(
      VamoEvent.closeAccepted,
      properties: {'trip_id': tripId, 'mode': 'explicit'},
    );
  }

  Future<void> objectToTripClose({
    required String tripId,
    required String reason,
  }) async {
    await _client.rpc('object_to_trip_close', params: {
      'p_trip_id': tripId,
      'p_reason': reason.trim(),
    });
    await syncTripFromRemote(tripId);
    _analytics.capture(
      VamoEvent.closeObjected,
      properties: {'trip_id': tripId, 'has_reason': true},
    );
  }

  Future<void> withdrawCloseObjection(String tripId) async {
    await _client.rpc(
      'withdraw_close_objection',
      params: {'p_trip_id': tripId},
    );
    await syncTripFromRemote(tripId);
  }

  Future<void> forceCloseTrip(String tripId) async {
    await _client.rpc('force_close_trip', params: {'p_trip_id': tripId});
    await syncTripFromRemote(tripId);
    _analytics.capture(
      VamoEvent.closeAccepted,
      properties: {'trip_id': tripId, 'mode': 'forced'},
    );
  }

  Future<void> cancelTrip(String tripId) async {
    await _client.rpc('cancel_trip', params: {'p_trip_id': tripId});
    await syncTripFromRemote(tripId);
    _analytics.capture(
      VamoEvent.tripCancelled,
      properties: {'trip_id': tripId},
    );
  }

  static const _tripSelectFields =
      'id, name, destination, start_date, end_date, owner_id, base_currency, '
      'lifecycle, close_requested_at, created_at';

  DateTime? _timestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value as String)?.toUtc();
  }

  String? _dateToIso(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }
}
