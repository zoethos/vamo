import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema v18 includes local trip photo metadata columns', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 20);

    final now = DateTime.utc(2026, 6, 18);
    final mediaCapturedAt = DateTime.utc(2026, 5, 1, 9, 30);
    await db.upsertTripPhoto(
      LocalTripPhotosCompanion(
        id: const Value('photo-1'),
        tripId: const Value('trip-1'),
        localPath: const Value('/tmp/photo-1.jpg'),
        storagePath: const Value('user-1/trip-1/photos/photo-1.jpg'),
        caption: const Value('Gelato stop'),
        capturedAt: Value(now),
        capturedLat: const Value(40.7128),
        capturedLng: const Value(-74.0060),
        mediaCapturedAt: Value(mediaCapturedAt),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
      ),
    );

    final rows = await db.watchTripPhotos('trip-1').first;
    expect(rows, hasLength(1));
    expect(rows.first.capturedLat, 40.7128);
    expect(rows.first.capturedLng, -74.0060);
    expect(rows.first.mediaCapturedAt, mediaCapturedAt.toLocal());
  });

  test('v17 to v18 migration adds local trip photo metadata columns', () async {
    final executor = NativeDatabase.memory();
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    await db.customStatement('DROP TABLE IF EXISTS local_trip_photos');
    await db.customStatement('''
CREATE TABLE local_trip_photos (
  id TEXT NOT NULL PRIMARY KEY,
  trip_id TEXT NOT NULL,
  local_path TEXT NULL,
  storage_path TEXT NULL,
  caption TEXT NULL,
  captured_at INTEGER NOT NULL,
  created_by TEXT NOT NULL,
  created_at INTEGER NOT NULL
)
''');
    await db.customStatement('PRAGMA user_version = 17');

    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 17, 18);

    final now = DateTime.utc(2026, 6, 18);
    await db.upsertTripPhoto(
      LocalTripPhotosCompanion(
        id: const Value('photo-1'),
        tripId: const Value('trip-1'),
        localPath: const Value('/tmp/photo-1.jpg'),
        capturedAt: Value(now),
        capturedLat: const Value(48.8566),
        capturedLng: const Value(2.3522),
        mediaCapturedAt: Value(DateTime.utc(2026, 5, 4, 8)),
        createdBy: const Value('user-1'),
        createdAt: Value(now),
      ),
    );

    final rows = await db.watchTripPhotos('trip-1').first;
    expect(rows, hasLength(1));
    expect(rows.first.capturedLat, 48.8566);
    expect(rows.first.capturedLng, 2.3522);
    expect(
      rows.first.mediaCapturedAt,
      DateTime.utc(2026, 5, 4, 8).toLocal(),
    );
  });
}
