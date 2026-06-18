import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/capture/capture_repository.dart';
import 'package:feature_split/src/capture/capture_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('watchTripPhotos emits photos persisted in Drift', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const tripId = 'trip-1';
    final capturedAt = DateTime.utc(2026, 6, 5, 12);
    final tempDir = await Directory.systemTemp.createTemp('vamo-capture-test');
    addTearDown(() => tempDir.delete(recursive: true));
    final photoFile = File('${tempDir.path}/photo-1.jpg');
    await photoFile.writeAsBytes(const [0xFF, 0xD8, 0xFF, 0xE0]);

    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value(tripId),
        name: const Value('Amalfi'),
        baseCurrency: const Value('EUR'),
        ownerId: const Value('user-1'),
        createdAt: Value(capturedAt),
        updatedAt: Value(capturedAt),
      ),
    );

    await db.upsertTripPhoto(
      LocalTripPhotosCompanion(
        id: const Value('photo-1'),
        tripId: const Value(tripId),
        localPath: Value(photoFile.path),
        capturedAt: Value(capturedAt),
        capturedLat: const Value(40.7128),
        capturedLng: const Value(-74.0060),
        mediaCapturedAt: Value(DateTime.utc(2026, 5, 1, 9, 30)),
        createdBy: const Value('user-1'),
        createdAt: Value(capturedAt),
      ),
    );

    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final queue = SyncQueue(db);
    final repo = CaptureRepository(
      db: db,
      client: client,
      syncQueue: queue,
      syncWorker: SyncWorker(
        queue: queue,
        client: client,
        analytics: DebugAnalytics(),
        flushWithoutSession: true,
        testExecute: (_) async {},
      ),
      tagCaptureLocation: false,
    );

    final photos = await repo.watchTripPhotos(tripId).first;
    expect(photos, hasLength(1));
    expect(photos.first.id, 'photo-1');
    expect(photos.first.tripId, tripId);
    expect(photos.first.displayPath, photoFile.path);
    expect(photos.first.capturedLat, 40.7128);
    expect(photos.first.capturedLng, -74.0060);
    expect(
      photos.first.mediaCapturedAt,
      DateTime.utc(2026, 5, 1, 9, 30).toLocal(),
    );
  });

  test('watchTripVideos emits videos persisted in Drift', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const tripId = 'trip-1';
    final capturedAt = DateTime.utc(2026, 6, 5, 12);
    final tempDir = await Directory.systemTemp.createTemp('vamo-capture-test');
    addTearDown(() => tempDir.delete(recursive: true));
    final videoFile = File('${tempDir.path}/video-1.mp4');
    await videoFile.writeAsBytes(const [0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70]);

    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value(tripId),
        name: const Value('Amalfi'),
        baseCurrency: const Value('EUR'),
        ownerId: const Value('user-1'),
        createdAt: Value(capturedAt),
        updatedAt: Value(capturedAt),
      ),
    );

    await db.upsertTripVideo(
      LocalTripVideosCompanion(
        id: const Value('video-1'),
        tripId: const Value(tripId),
        localPath: Value(videoFile.path),
        capturedAt: Value(capturedAt),
        createdBy: const Value('user-1'),
        createdAt: Value(capturedAt),
      ),
    );

    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final queue = SyncQueue(db);
    final repo = CaptureRepository(
      db: db,
      client: client,
      syncQueue: queue,
      syncWorker: SyncWorker(
        queue: queue,
        client: client,
        analytics: DebugAnalytics(),
        flushWithoutSession: true,
        testExecute: (_) async {},
      ),
      tagCaptureLocation: false,
    );

    final videos = await repo.watchTripVideos(tripId).first;
    expect(videos, hasLength(1));
    expect(videos.first.id, 'video-1');
    expect(videos.first.tripId, tripId);
    expect(videos.first.displayPath, videoFile.path);
  });

  test('media cache local path updates are partial-safe', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const tripId = 'trip-1';
    final capturedAt = DateTime.utc(2026, 6, 5, 12);

    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value(tripId),
        name: const Value('Amalfi'),
        baseCurrency: const Value('EUR'),
        ownerId: const Value('user-1'),
        createdAt: Value(capturedAt),
        updatedAt: Value(capturedAt),
      ),
    );
    await db.upsertTripPhoto(
      LocalTripPhotosCompanion(
        id: const Value('photo-remote'),
        tripId: const Value(tripId),
        storagePath: const Value('user-1/trip-1/photos/photo-remote.jpg'),
        capturedAt: Value(capturedAt),
        createdBy: const Value('user-1'),
        createdAt: Value(capturedAt),
      ),
    );
    await db.upsertTripVideo(
      LocalTripVideosCompanion(
        id: const Value('video-remote'),
        tripId: const Value(tripId),
        storagePath: const Value('user-1/trip-1/videos/video-remote.mp4'),
        capturedAt: Value(capturedAt),
        createdBy: const Value('user-1'),
        createdAt: Value(capturedAt),
      ),
    );

    await expectLater(
      db.upsertTripPhoto(
        const LocalTripPhotosCompanion(
          id: Value('photo-remote'),
          localPath: Value('/tmp/photo-remote.jpg'),
        ),
      ),
      throwsA(isA<InvalidDataException>()),
    );
    await expectLater(
      db.upsertTripVideo(
        const LocalTripVideosCompanion(
          id: Value('video-remote'),
          localPath: Value('/tmp/video-remote.mp4'),
        ),
      ),
      throwsA(isA<InvalidDataException>()),
    );

    expect(
      (await (db.select(db.localTripPhotos)
                ..where((p) => p.id.equals('photo-remote')))
              .getSingle())
          .localPath,
      equals(null),
    );
    expect(
      (await (db.select(db.localTripVideos)
                ..where((v) => v.id.equals('video-remote')))
              .getSingle())
          .localPath,
      equals(null),
    );

    await db.updateTripPhotoFields(
      'photo-remote',
      const LocalTripPhotosCompanion(localPath: Value('/tmp/photo-remote.jpg')),
    );
    await db.updateTripVideoFields(
      'video-remote',
      const LocalTripVideosCompanion(localPath: Value('/tmp/video-remote.mp4')),
    );

    expect(
      (await (db.select(db.localTripPhotos)
                ..where((p) => p.id.equals('photo-remote')))
              .getSingle())
          .localPath,
      '/tmp/photo-remote.jpg',
    );
    expect(
      (await (db.select(db.localTripVideos)
                ..where((v) => v.id.equals('video-remote')))
              .getSingle())
          .localPath,
      '/tmp/video-remote.mp4',
    );
  });

  test('watchTripVideos defers remote video download until playback', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const tripId = 'trip-1';
    final capturedAt = DateTime.utc(2026, 6, 5, 12);

    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value(tripId),
        name: const Value('Amalfi'),
        baseCurrency: const Value('EUR'),
        ownerId: const Value('user-1'),
        createdAt: Value(capturedAt),
        updatedAt: Value(capturedAt),
      ),
    );

    await db.upsertTripVideo(
      LocalTripVideosCompanion(
        id: const Value('video-remote'),
        tripId: const Value(tripId),
        storagePath: const Value('user-1/trip-1/videos/video-remote.mp4'),
        capturedAt: Value(capturedAt),
        createdBy: const Value('user-1'),
        createdAt: Value(capturedAt),
      ),
    );

    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final queue = SyncQueue(db);
    final repo = CaptureRepository(
      db: db,
      client: client,
      syncQueue: queue,
      syncWorker: SyncWorker(
        queue: queue,
        client: client,
        analytics: DebugAnalytics(),
        flushWithoutSession: true,
        testExecute: (_) async {},
      ),
      tagCaptureLocation: false,
    );

    final videos = await repo.watchTripVideos(tripId).first;
    expect(videos, hasLength(1));
    expect(videos.first.id, 'video-remote');
    expect(videos.first.displayPath, null);
    expect(videos.first.loadError, null);
    expect(videos.first.hasRemoteStoragePath, isTrue);
    expect(videos.first.storagePath, 'user-1/trip-1/videos/video-remote.mp4');
  });

  test('video storage helpers guard upload size and content type', () async {
    expect(CaptureStorage.videoContentTypeForPath('clip.mp4'), 'video/mp4');
    expect(
      CaptureStorage.videoContentTypeForPath('clip.mov'),
      'video/quicktime',
    );
    expect(
      CaptureStorage.videoContentTypeForPath('clip.unknown'),
      'application/octet-stream',
    );

    final tempDir = await Directory.systemTemp.createTemp('vamo-video-size');
    addTearDown(() => tempDir.delete(recursive: true));
    final tooLarge = File('${tempDir.path}/large.mp4');
    final raf = await tooLarge.open(mode: FileMode.write);
    addTearDown(() async {
      try {
        await raf.close();
      } catch (_) {
        // The file may already be closed by the test body.
      }
    });
    await raf.setPosition(CaptureStorage.maxVideoBytes);
    await raf.writeByte(0);
    await raf.close();

    expect(
      CaptureStorage.ensureVideoSizeAllowed(tooLarge.path),
      throwsA(isA<FileSystemException>()),
    );
  });
}
