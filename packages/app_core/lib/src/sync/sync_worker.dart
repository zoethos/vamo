import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics/action_failure.dart';
import '../analytics/analytics.dart';
import '../db/app_database.dart';
import '../storage/storage_paths.dart';
import 'sync_operation.dart';
import 'sync_queue.dart';

/// Drains the outbox to Supabase — idempotent upserts, dead-letter after max attempts.
class SyncWorker {
  SyncWorker({
    required SyncQueue queue,
    required SupabaseClient client,
    AppDatabase? db,
    Analytics? analytics,
    @visibleForTesting Future<void> Function(LocalSyncOutboxData)? testExecute,
    @visibleForTesting bool flushWithoutSession = false,
  })  : _queue = queue,
        _client = client,
        _db = db,
        _analytics = analytics,
        _testExecute = testExecute,
        _flushWithoutSession = flushWithoutSession;

  final SyncQueue _queue;
  final SupabaseClient _client;
  final AppDatabase? _db;
  final Analytics? _analytics;
  final Future<void> Function(LocalSyncOutboxData)? _testExecute;
  final bool _flushWithoutSession;

  bool _flushing = false;

  /// Processes pending ops until empty, offline, or only dead-letter rows remain.
  Future<int> flush() async {
    if (_flushing) return 0;
    if (!_flushWithoutSession && _client.auth.currentUser == null) return 0;

    _flushing = true;
    var processed = 0;
    try {
      while (true) {
        final batch = await _queue.pending();
        if (batch.isEmpty) break;

        var madeProgress = false;
        for (final op in batch) {
          if (op.attempts >= SyncQueue.maxAttempts) {
            await _deadLetter(op);
            madeProgress = true;
            continue;
          }

          try {
            await _execute(op);
            await _queue.remove(op.id);
            processed++;
            madeProgress = true;
          } catch (e) {
            if (isDuplicateKeyError(e)) {
              await _queue.remove(op.id);
              processed++;
              madeProgress = true;
              continue;
            }
            final attempts = await _queue.recordFailure(op.id, e.toString());
            if (attempts != null && attempts >= SyncQueue.maxAttempts) {
              await _deadLetter(op);
              madeProgress = true;
            }
          }
        }
        if (!madeProgress) break;
      }
    } finally {
      _flushing = false;
    }
    return processed;
  }

  Future<void> _deadLetter(LocalSyncOutboxData op) async {
    final kind = SyncKind.parse(op.kind);
    final analytics = _analytics;
    if (kind == SyncKind.receiptUpload && analytics != null) {
      analytics.reportActionFailed(
        screen: 'sync',
        action: 'attach_receipt',
        error: Exception(op.lastError ?? 'receipt_upload_dead_letter'),
      );
    }
    await _queue.remove(op.id);
    if (kDebugMode) {
      debugPrint('[sync] dead-letter ${op.kind} ${op.id}');
    }
  }

  Future<void> _execute(LocalSyncOutboxData op) async {
    if (_testExecute != null) {
      return _testExecute(op);
    }
    final kind = SyncKind.parse(op.kind);
    if (kind == null) {
      throw StateError('Unknown sync kind: ${op.kind}');
    }
    final payload = decodePayload(op.payload);

    switch (kind) {
      case SyncKind.expenseInsert:
        final expense = Map<String, dynamic>.from(
          payload['expense'] as Map,
        );
        await _client.from('expenses').upsert(expense, onConflict: 'id');
        final shares = (payload['shares'] as List)
            .cast<Map<String, dynamic>>()
            .map(Map<String, dynamic>.from)
            .toList();
        if (shares.isNotEmpty) {
          await _client.from('expense_shares').upsert(shares, onConflict: 'id');
        }
        break;
      case SyncKind.receiptUpload:
        final expenseId = payload['expense_id'] as String;
        final localPath = payload['local_path'] as String;
        final storagePath = payload['storage_path'] as String;
        final bytes = await File(localPath).readAsBytes();
        await _client.storage.from(StoragePaths.capturesBucket).uploadBinary(
              storagePath,
              bytes,
              fileOptions: FileOptions(
                contentType: _contentTypeForPath(localPath),
                upsert: true,
              ),
            );
        await _client.from('expenses').upsert(
              {'id': expenseId, 'receipt_path': storagePath},
              onConflict: 'id',
            );
        final db = _db;
        if (db != null) {
          await db.upsertExpense(
            LocalExpensesCompanion(
              id: Value(expenseId),
              receiptPath: Value(storagePath),
            ),
          );
        }
        break;
      case SyncKind.settlementInsert:
        await _client.from('settlements').upsert(
              Map<String, dynamic>.from(payload),
              onConflict: 'id',
            );
        break;
      case SyncKind.settlementUpdate:
        await _client
            .from('settlements')
            .update({'status': payload['status']})
            .eq('id', payload['id'] as String);
        break;
      case SyncKind.tripNoteInsert:
        await _client.from('trip_notes').upsert(
              Map<String, dynamic>.from(payload),
              onConflict: 'id',
            );
        break;
    }
  }

  static String _contentTypeForPath(String path) {
    final ext = path.contains('.') ? '.${path.split('.').last.toLowerCase()}' : '.jpg';
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
      case '.heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  /// Postgres unique violation or PostgREST duplicate — safe to drop op.
  @visibleForTesting
  static bool isDuplicateKeyError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('23505') ||
        text.contains('duplicate key') ||
        text.contains('already exists');
  }
}
