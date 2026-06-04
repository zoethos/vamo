import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'payment_links.dart';
import 'settle_up.dart';

final settlementsRepositoryProvider = Provider<SettlementsRepository>((ref) {
  return SettlementsRepository(
    db: ref.watch(appDatabaseProvider),
    client: ref.watch(supabaseClientProvider),
    analytics: ref.watch(analyticsProvider),
    syncQueue: ref.watch(syncQueueProvider),
    syncWorker: ref.watch(syncWorkerProvider),
  );
});

/// Slice 4 — mark + confirm settlements; Drift-first, Supabase on write.
class SettlementsRepository {
  SettlementsRepository({
    required AppDatabase db,
    required SupabaseClient client,
    required Analytics analytics,
    required SyncQueue syncQueue,
    required SyncWorker syncWorker,
  })  : _db = db,
        _client = client,
        _analytics = analytics,
        _syncQueue = syncQueue,
        _syncWorker = syncWorker;

  final AppDatabase _db;
  final SupabaseClient _client;
  final Analytics _analytics;
  final SyncQueue _syncQueue;
  final SyncWorker _syncWorker;
  final _uuid = const Uuid();

  Stream<List<SettlementRecord>> watchTripSettlements(String tripId) {
    return _db.watchTripSettlements(tripId).map(
          (rows) => rows.map(SettlementRecord.fromLocal).toList(),
        );
  }

  ({Map<String, int> out, Map<String, int> in_}) settlementTotals(
    Iterable<SettlementRecord> rows,
  ) {
    final out = <String, int>{};
    final in_ = <String, int>{};
    for (final s in rows) {
      out[s.fromUserId] = (out[s.fromUserId] ?? 0) + s.amountCents;
      in_[s.toUserId] = (in_[s.toUserId] ?? 0) + s.amountCents;
    }
    return (out: out, in_: in_);
  }

  Future<SettlementRecord> markSettled({
    required String tripId,
    required SettlementLine line,
    required String currency,
    required PaymentMethod method,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be signed in to mark a settlement');
    }
    if (userId != line.fromUserId) {
      throw StateError('Only the payer can mark this settlement');
    }

    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    await _db.upsertSettlement(
      LocalSettlementsCompanion(
        id: Value(id),
        tripId: Value(tripId),
        fromUser: Value(line.fromUserId),
        toUser: Value(line.toUserId),
        amountCents: Value(line.cents),
        currency: Value(currency),
        status: const Value('marked'),
        method: Value(method.id),
        createdAt: Value(now),
      ),
    );

    await _syncQueue.enqueue(
      kind: SyncKind.settlementInsert,
      payload: {
        'id': id,
        'trip_id': tripId,
        'from_user': line.fromUserId,
        'to_user': line.toUserId,
        'amount_cents': line.cents,
        'currency': currency,
        'status': 'marked',
        'method': method.id,
      },
    );
    unawaited(_syncWorker.flush());

    _analytics.capture(
      VamoEvent.settleMarked,
      properties: {
        'trip_id': tripId,
        'settlement_id': id,
        'amount_cents': line.cents,
        'method': method.id,
      },
    );

    return SettlementRecord(
      id: id,
      tripId: tripId,
      fromUserId: line.fromUserId,
      toUserId: line.toUserId,
      amountCents: line.cents,
      currency: currency,
      status: SettlementStatus.marked,
      method: method.id,
      createdAt: now,
    );
  }

  Future<void> confirmSettlement(String settlementId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be signed in to confirm');
    }

    final row = await (_db.select(_db.localSettlements)
          ..where((s) => s.id.equals(settlementId)))
        .getSingleOrNull();
    if (row == null) throw StateError('Settlement not found');
    if (row.toUser != userId) {
      throw StateError('Only the recipient can confirm');
    }
    if (row.status == 'confirmed') return;

    await _db.upsertSettlement(
      LocalSettlementsCompanion(
        id: Value(settlementId),
        status: const Value('confirmed'),
      ),
    );

    await _syncQueue.enqueue(
      kind: SyncKind.settlementUpdate,
      payload: {'id': settlementId, 'status': 'confirmed'},
    );
    unawaited(_syncWorker.flush());

    _analytics.capture(
      VamoEvent.settleConfirmed,
      properties: {
        'trip_id': row.tripId,
        'settlement_id': settlementId,
      },
    );
  }

  /// Removes a marked (unconfirmed) settlement — payer cancel or recipient reject.
  /// Debt resurfaces in balances because netting no longer includes this row.
  Future<void> revokeMarkedSettlement(String settlementId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be signed in');
    }

    final row = await (_db.select(_db.localSettlements)
          ..where((s) => s.id.equals(settlementId)))
        .getSingleOrNull();
    if (row == null) throw StateError('Settlement not found');
    if (row.status != 'marked') {
      throw StateError('Only marked settlements can be revoked');
    }
    final isPayer = row.fromUser == userId;
    final isRecipient = row.toUser == userId;
    if (!isPayer && !isRecipient) {
      throw StateError('Only the payer or recipient can revoke');
    }

    await (_db.delete(_db.localSettlements)..where((s) => s.id.equals(settlementId)))
        .go();

    try {
      await _client.from('settlements').delete().eq('id', settlementId);
    } catch (e) {
      await _db.upsertSettlement(
        LocalSettlementsCompanion(
          id: Value(row.id),
          tripId: Value(row.tripId),
          fromUser: Value(row.fromUser),
          toUser: Value(row.toUser),
          amountCents: Value(row.amountCents),
          currency: Value(row.currency),
          status: Value(row.status),
          method: Value(row.method),
          createdAt: Value(row.createdAt),
        ),
      );
      rethrow;
    }
  }

  Future<void> syncSettlementsForTrips(
    Iterable<String> tripIds, {
    Set<String> excludeSettlementIds = const {},
  }) async {
    final ids = tripIds.toList();
    if (ids.isEmpty) return;

    final rows = await _client
        .from('settlements')
        .select(
          'id, trip_id, from_user, to_user, amount_cents, currency, status, method, created_at',
        )
        .inFilter('trip_id', ids)
        .order('created_at', ascending: false);

    final settlementRows = (rows as List).cast<Map<String, dynamic>>();

    for (final row in settlementRows) {
      await _db.upsertSettlement(
        LocalSettlementsCompanion(
          id: Value(row['id'] as String),
          tripId: Value(row['trip_id'] as String),
          fromUser: Value(row['from_user'] as String),
          toUser: Value(row['to_user'] as String),
          amountCents: Value((row['amount_cents'] as num).toInt()),
          currency: Value(row['currency'] as String),
          status: Value(row['status'] as String),
          method: Value(row['method'] as String?),
          createdAt: Value(DateTime.parse(row['created_at'] as String)),
        ),
      );
    }

    for (final tripId in ids) {
      final remoteIds = settlementRows
          .where((r) => r['trip_id'] == tripId)
          .map((r) => r['id'] as String)
          .toSet();
      await _db.pruneSettlementsForTrip(
        tripId,
        remoteIds,
        excludeIds: excludeSettlementIds,
      );
    }
  }
}

enum SettlementStatus { marked, confirmed }

class SettlementRecord {
  const SettlementRecord({
    required this.id,
    required this.tripId,
    required this.fromUserId,
    required this.toUserId,
    required this.amountCents,
    required this.currency,
    required this.status,
    this.method,
    required this.createdAt,
  });

  factory SettlementRecord.fromLocal(LocalSettlement row) => SettlementRecord(
        id: row.id,
        tripId: row.tripId,
        fromUserId: row.fromUser,
        toUserId: row.toUser,
        amountCents: row.amountCents,
        currency: row.currency,
        status: row.status == 'confirmed'
            ? SettlementStatus.confirmed
            : SettlementStatus.marked,
        method: row.method,
        createdAt: row.createdAt,
      );

  final String id;
  final String tripId;
  final String fromUserId;
  final String toUserId;
  final int amountCents;
  final String currency;
  final SettlementStatus status;
  final String? method;
  final DateTime createdAt;

  bool get awaitingConfirm => status == SettlementStatus.marked;

  bool matchesLine(SettlementLine line) =>
      fromUserId == line.fromUserId &&
      toUserId == line.toUserId &&
      amountCents == line.cents;
}
