import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('isDuplicateKeyError', () {
    test('detects postgres 23505', () {
      expect(
        SyncWorker.isDuplicateKeyError(
          const PostgrestException(
            message: '23505 duplicate key',
            code: '23505',
          ),
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

  test('receipt_upload succeeds after retry', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final queue = SyncQueue(db);

    await queue.enqueue(
      kind: SyncKind.receiptUpload,
      payload: {
        'expense_id': 'e1',
        'local_path': '/tmp/receipt.jpg',
        'storage_path': 'u1/t1/receipts/e1.jpg',
      },
    );

    final client = SupabaseClient('http://localhost', 'anon-key');
    var attempts = 0;
    final worker = SyncWorker(
      queue: queue,
      client: client,
      flushWithoutSession: true,
      testExecute: (op) async {
        if (op.kind == SyncKind.receiptUpload.value) {
          attempts++;
          if (attempts == 1) throw Exception('network blip');
        }
      },
    );

    await worker.flush();
    expect(attempts, 1);
    expect(await queue.pending(), isNotEmpty);

    final processed = await worker.flush();
    expect(processed, 1);
    expect(attempts, 2);
    expect(await queue.pending(), isEmpty);
  });

  test('trip_photo_upload succeeds after retry', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final queue = SyncQueue(db);

    await queue.enqueue(
      kind: SyncKind.tripPhotoUpload,
      payload: {
        'photo_id': 'p1',
        'trip_id': 't1',
        'local_path': '/tmp/photo.jpg',
        'storage_path': 'u1/t1/p1.jpg',
        'caption': 'Lunch',
        'captured_at': DateTime.utc(2026, 6, 18, 12).toIso8601String(),
        'created_by': 'u1',
      },
    );

    final client = SupabaseClient('http://localhost', 'anon-key');
    var attempts = 0;
    final worker = SyncWorker(
      queue: queue,
      client: client,
      flushWithoutSession: true,
      testExecute: (op) async {
        if (op.kind == SyncKind.tripPhotoUpload.value) {
          attempts++;
          if (attempts == 1) throw Exception('network blip');
        }
      },
    );

    await worker.flush();
    expect(attempts, 1);
    expect(await queue.countPendingMediaUploads(), 1);

    final processed = await worker.flush();
    expect(processed, 1);
    expect(attempts, 2);
    expect(await queue.pending(), isEmpty);
  });

  test('trip_video_upload dead-letter fires action_failed', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final queue = SyncQueue(db);
    final analytics = _RecordingAnalytics();

    await queue.enqueue(
      kind: SyncKind.tripVideoUpload,
      payload: {
        'video_id': 'v1',
        'trip_id': 't1',
        'local_path': '/tmp/video.mp4',
        'storage_path': 'u1/t1/videos/v1.mp4',
        'captured_at': DateTime.utc(2026, 6, 18, 12).toIso8601String(),
        'created_by': 'u1',
      },
    );

    final client = SupabaseClient('http://localhost', 'anon-key');
    final worker = SyncWorker(
      queue: queue,
      client: client,
      analytics: analytics,
      flushWithoutSession: true,
      testExecute: (op) async {
        if (op.kind == SyncKind.tripVideoUpload.value) {
          throw Exception('permanent storage error');
        }
      },
    );

    for (var i = 0; i < SyncQueue.maxAttempts; i++) {
      await worker.flush();
    }

    expect(await queue.pending(), isEmpty);
    expect(
      analytics.events.where((e) => e['event'] == VamoEvent.actionFailed),
      hasLength(1),
    );
    final props = analytics.events.first['properties']! as Map<String, Object?>;
    expect(props['action'], 'upload_video_remote');
  });

  test('receipt_upload dead-letter fires action_failed', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final queue = SyncQueue(db);
    final analytics = _RecordingAnalytics();

    await queue.enqueue(
      kind: SyncKind.receiptUpload,
      payload: {
        'expense_id': 'e2',
        'local_path': '/tmp/receipt2.jpg',
        'storage_path': 'u1/t1/receipts/e2.jpg',
      },
    );

    final client = SupabaseClient('http://localhost', 'anon-key');
    final worker = SyncWorker(
      queue: queue,
      client: client,
      analytics: analytics,
      flushWithoutSession: true,
      testExecute: (op) async {
        if (op.kind == SyncKind.receiptUpload.value) {
          throw Exception('permanent storage error');
        }
      },
    );

    for (var i = 0; i < SyncQueue.maxAttempts; i++) {
      await worker.flush();
    }

    expect(await queue.pending(), isEmpty);
    expect(
      analytics.events.where((e) => e['event'] == VamoEvent.actionFailed),
      hasLength(1),
    );
    final props = analytics.events.first['properties']! as Map<String, Object?>;
    expect(props['action'], 'attach_receipt');
  });
}

class _RecordingAnalytics implements Analytics {
  final events = <Map<String, Object?>>[];

  @override
  void capture(VamoEvent event, {Map<String, Object?> properties = const {}}) {
    events.add({'event': event, 'properties': properties});
  }

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<void> reset() async {}
}
