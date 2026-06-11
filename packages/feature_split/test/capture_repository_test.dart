import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/capture/capture_repository.dart';
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
    );

    final photos = await repo.watchTripPhotos(tripId).first;
    expect(photos, hasLength(1));
    expect(photos.first.id, 'photo-1');
    expect(photos.first.tripId, tripId);
    expect(photos.first.displayPath, photoFile.path);
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
    );

    final videos = await repo.watchTripVideos(tripId).first;
    expect(videos, hasLength(1));
    expect(videos.first.id, 'video-1');
    expect(videos.first.tripId, tripId);
    expect(videos.first.displayPath, videoFile.path);
  });
}
