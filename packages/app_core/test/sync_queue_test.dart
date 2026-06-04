import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SyncQueue queue;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    queue = SyncQueue(db);
  });

  tearDown(() => db.close());

  test('recordFailure increments attempts', () async {
    await queue.enqueue(
      kind: SyncKind.tripNoteInsert,
      payload: {'id': 'n1', 'trip_id': 't1', 'body': 'hi'},
    );
    final pending = await queue.pending();
    await queue.recordFailure(pending.single.id, 'offline');
    final row = await db.select(db.localSyncOutbox).getSingle();
    expect(row.attempts, 1);
    expect(row.lastError, 'offline');
  });

  test('pending omits rows at maxAttempts', () async {
    await queue.enqueue(
      kind: SyncKind.tripNoteInsert,
      payload: {'id': 'n1', 'trip_id': 't1'},
    );
    final id = (await queue.pending()).single.id;
    for (var i = 0; i < SyncQueue.maxAttempts; i++) {
      await queue.recordFailure(id, 'fail');
    }
    expect(await queue.pending(), isEmpty);
  });

  test('collectPendingEntityIds includes queued expense id', () async {
    await queue.enqueue(
      kind: SyncKind.expenseInsert,
      payload: {
        'expense': {'id': 'e-offline', 'trip_id': 't1'},
        'shares': <Map<String, dynamic>>[],
      },
    );
    final ids = await queue.collectPendingEntityIds();
    expect(ids.expenseIds, contains('e-offline'));
  });
}
