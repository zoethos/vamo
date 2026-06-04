import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('isDuplicateKeyError', () {
    test('detects postgres 23505', () {
      expect(
        SyncWorker.isDuplicateKeyError(
          const PostgrestException(message: '23505 duplicate key', code: '23505'),
        ),
        isTrue,
      );
    });

    test('detects duplicate key text', () {
      expect(
        SyncWorker.isDuplicateKeyError(Exception('duplicate key value')),
        isTrue,
      );
    });

    test('ignores unrelated errors', () {
      expect(
        SyncWorker.isDuplicateKeyError(Exception('connection reset')),
        isFalse,
      );
    });
  });

  test('flush drops duplicate-key op and continues the queue', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final queue = SyncQueue(db);

    await queue.enqueue(
      kind: SyncKind.expenseInsert,
      payload: {
        'expense': {'id': 'e1', 'trip_id': 't1'},
        'shares': <Map<String, dynamic>>[],
      },
    );
    await queue.enqueue(
      kind: SyncKind.tripNoteInsert,
      payload: {'id': 'n1', 'trip_id': 't1', 'body': 'ok'},
    );

    final client = SupabaseClient('http://localhost', 'anon-key');
    final worker = SyncWorker(
      queue: queue,
      client: client,
      flushWithoutSession: true,
      testExecute: (op) async {
        if (op.kind == SyncKind.expenseInsert.value) {
          throw const PostgrestException(
            message: 'duplicate key value violates unique constraint',
            code: '23505',
          );
        }
      },
    );

    final processed = await worker.flush();
    expect(processed, 2);
    expect(await queue.pending(), isEmpty);
  });

  test('flush dead-letters poison op without blocking the next op', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final queue = SyncQueue(db);

    await queue.enqueue(
      kind: SyncKind.settlementInsert,
      payload: {'id': 's1', 'trip_id': 't1', 'status': 'pending'},
    );
    await queue.enqueue(
      kind: SyncKind.tripNoteInsert,
      payload: {'id': 'n2', 'trip_id': 't1'},
    );

    final client = SupabaseClient('http://localhost', 'anon-key');
    var poisonCalls = 0;
    final worker = SyncWorker(
      queue: queue,
      client: client,
      flushWithoutSession: true,
      testExecute: (op) async {
        if (op.kind == SyncKind.settlementInsert.value) {
          poisonCalls++;
          throw Exception('permanent schema error');
        }
      },
    );

    for (var i = 0; i < SyncQueue.maxAttempts; i++) {
      await worker.flush();
    }
    expect(poisonCalls, greaterThanOrEqualTo(SyncQueue.maxAttempts));
    expect(await queue.pending(), isEmpty);
    expect(await queue.countPending(), 0);
  });
}
