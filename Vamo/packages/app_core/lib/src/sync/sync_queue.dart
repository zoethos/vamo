import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import 'sync_operation.dart';

/// Entity IDs still in the outbox — must not be pruned during pull.
class OutboxEntityIds {
  const OutboxEntityIds({
    this.expenseIds = const {},
    this.settlementIds = const {},
    this.tripNoteIds = const {},
  });

  final Set<String> expenseIds;
  final Set<String> settlementIds;
  final Set<String> tripNoteIds;
}

/// Appends optimistic writes for the background sync worker.
class SyncQueue {
  SyncQueue(this._db);

  final AppDatabase _db;
  final _uuid = const Uuid();

  /// Ops exceeding this are dropped so one poison row cannot jam the queue.
  static const maxAttempts = 8;

  Future<void> enqueue({
    required SyncKind kind,
    required Map<String, dynamic> payload,
  }) async {
    final now = DateTime.now().toUtc();
    await _db.into(_db.localSyncOutbox).insert(
          LocalSyncOutboxCompanion(
            id: Value(_uuid.v4()),
            kind: Value(kind.value),
            payload: Value(encodePayload(payload)),
            createdAt: Value(now),
          ),
        );
  }

  Future<List<LocalSyncOutboxData>> pending({int limit = 50}) {
    return (_db.select(_db.localSyncOutbox)
          ..where((o) => o.attempts.isSmallerThanValue(maxAttempts))
          ..orderBy([(o) => OrderingTerm.asc(o.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<void> remove(String id) {
    return (_db.delete(_db.localSyncOutbox)..where((o) => o.id.equals(id)))
        .go();
  }

  /// Returns new attempt count, or null if the row was removed.
  Future<int?> recordFailure(String id, String error) async {
    final row = await (_db.select(_db.localSyncOutbox)
          ..where((o) => o.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    final next = row.attempts + 1;
    await (_db.update(_db.localSyncOutbox)..where((o) => o.id.equals(id))).write(
          LocalSyncOutboxCompanion(
            attempts: Value(next),
            lastError: Value(error),
          ),
        );
    return next;
  }

  Future<int> countPending() async {
    final rows = await (_db.select(_db.localSyncOutbox)
          ..where((o) => o.attempts.isSmallerThanValue(maxAttempts)))
        .get();
    return rows.length;
  }

  Future<void> clear() {
    return _db.delete(_db.localSyncOutbox).go();
  }

  /// IDs referenced by queued writes — keep local rows until push succeeds.
  Future<OutboxEntityIds> collectPendingEntityIds() async {
    final rows = await _db.select(_db.localSyncOutbox).get();
    final expenseIds = <String>{};
    final settlementIds = <String>{};
    final tripNoteIds = <String>{};

    for (final row in rows) {
      if (row.attempts >= maxAttempts) continue;
      final kind = SyncKind.parse(row.kind);
      if (kind == null) continue;
      final payload = decodePayload(row.payload);
      switch (kind) {
        case SyncKind.expenseInsert:
          final expense = payload['expense'] as Map<String, dynamic>?;
          if (expense?['id'] is String) expenseIds.add(expense!['id'] as String);
        case SyncKind.settlementInsert:
          if (payload['id'] is String) {
            settlementIds.add(payload['id'] as String);
          }
        case SyncKind.settlementUpdate:
          if (payload['id'] is String) {
            settlementIds.add(payload['id'] as String);
          }
        case SyncKind.tripNoteInsert:
          if (payload['id'] is String) tripNoteIds.add(payload['id'] as String);
      }
    }

    return OutboxEntityIds(
      expenseIds: expenseIds,
      settlementIds: settlementIds,
      tripNoteIds: tripNoteIds,
    );
  }
}
