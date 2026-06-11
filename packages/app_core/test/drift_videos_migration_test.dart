import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v17 includes local trip videos table', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 17);

    final now = DateTime.utc(2026, 6, 11);
    await db.upsertTripVideo(
      LocalTripVideosCompanion(
        id: const Value('video-1'),
        tripId: const Value('trip-1'),
        localPath: const Value('/tmp/video-1.mp4'),
        storagePath: const Value('user-1/trip-1/videos/video-1.mp4'),
        caption: const Value('Sunset'),
        capturedAt: Value(now),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
      ),
    );

    final rows = await db.watchTripVideos('trip-1').first;
    expect(rows, hasLength(1));
    expect(rows.first.storagePath, 'user-1/trip-1/videos/video-1.mp4');
    expect(rows.first.caption, 'Sunset');
  });

  test('v16 to v17 migration creates local trip videos table', () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await db.customStatement('DROP TABLE IF EXISTS local_trip_videos');
    await db.customStatement('PRAGMA user_version = 16');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 16, 17);

    final now = DateTime.utc(2026, 6, 11);
    await db.upsertTripVideo(
      LocalTripVideosCompanion(
        id: const Value('video-1'),
        tripId: const Value('trip-1'),
        localPath: const Value('/tmp/video-1.mp4'),
        capturedAt: Value(now),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
      ),
    );

    final rows = await db.watchTripVideos('trip-1').first;
    expect(rows, hasLength(1));
  });
}
