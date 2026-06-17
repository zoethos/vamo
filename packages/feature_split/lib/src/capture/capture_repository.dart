import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'capture_models.dart';
import 'capture_photo_metadata.dart';
import 'capture_storage.dart';

final captureRepositoryProvider = Provider<CaptureRepository>((ref) {
  return CaptureRepository(
    db: ref.watch(appDatabaseProvider),
    client: ref.watch(supabaseClientProvider),
    syncQueue: ref.watch(syncQueueProvider),
    syncWorker: ref.watch(syncWorkerProvider),
    tagCaptureLocation: ref.watch(captureLocationTaggingProvider),
    analytics: ref.watch(analyticsProvider),
  );
});

/// Slice 8 — notes + photos, Drift-first with Supabase on write.
class CaptureRepository {
  CaptureRepository({
    required AppDatabase db,
    required SupabaseClient client,
    required SyncQueue syncQueue,
    required SyncWorker syncWorker,
    required bool tagCaptureLocation,
    Analytics? analytics,
  })  : _db = db,
        _client = client,
        _syncQueue = syncQueue,
        _syncWorker = syncWorker,
        _tagCaptureLocation = tagCaptureLocation,
        _analytics = analytics;

  final AppDatabase _db;
  final SupabaseClient _client;
  final SyncQueue _syncQueue;
  final SyncWorker _syncWorker;
  final bool _tagCaptureLocation;
  final Analytics? _analytics;
  final _uuid = const Uuid();

  static const _capturesBucket = StoragePaths.capturesBucket;

  Stream<List<TripNoteView>> watchTripNotes(String tripId) {
    return _db.watchTripNotes(tripId).map(
          (rows) => rows
              .map(
                (r) => TripNoteView(
                  id: r.id,
                  tripId: r.tripId,
                  title: r.title,
                  body: r.body,
                  capturedAt: r.capturedAt,
                ),
              )
              .toList(),
        );
  }

  Stream<List<TripPhotoView>> watchTripPhotos(String tripId) async* {
    await for (final rows in _db.watchTripPhotos(tripId)) {
      final views = <TripPhotoView>[];
      for (final row in rows) {
        final loaded = await loadPhotoAttachment(row);
        if (loaded.displayPath != null ||
            loaded.loadError != null ||
            loaded.hasRemoteStoragePath) {
          views.add(loaded);
        }
      }
      yield views;
    }
  }

  Stream<List<TripVideoView>> watchTripVideos(String tripId) async* {
    await for (final rows in _db.watchTripVideos(tripId)) {
      final views = <TripVideoView>[];
      for (final row in rows) {
        final loaded = await loadVideoAttachment(row);
        if (loaded.displayPath != null ||
            loaded.loadError != null ||
            loaded.hasRemoteStoragePath) {
          views.add(loaded);
        }
      }
      yield views;
    }
  }

  Future<TripPhotoView> loadPhotoAttachment(LocalTripPhoto row) async {
    final local = row.localPath;
    if (local != null && local.isNotEmpty && await File(local).exists()) {
      return TripPhotoView(
        id: row.id,
        tripId: row.tripId,
        displayPath: local,
        caption: row.caption,
        capturedAt: row.capturedAt,
        capturedLat: row.capturedLat,
        capturedLng: row.capturedLng,
        mediaCapturedAt: row.mediaCapturedAt,
        storagePath: row.storagePath,
      );
    }

    final remote = row.storagePath;
    if (remote == null || remote.isEmpty) {
      return TripPhotoView(
        id: row.id,
        tripId: row.tripId,
        displayPath: local,
        caption: row.caption,
        capturedAt: row.capturedAt,
        capturedLat: row.capturedLat,
        capturedLng: row.capturedLng,
        mediaCapturedAt: row.mediaCapturedAt,
      );
    }

    final result = await CaptureStorage.cachePhotoFromStorage(
      client: _client,
      tripId: row.tripId,
      photoId: row.id,
      storagePath: remote,
    );
    if (result.isSuccess) {
      await _db.upsertTripPhoto(
        LocalTripPhotosCompanion(
          id: Value(row.id),
          localPath: Value(result.localPath),
        ),
      );
      return TripPhotoView(
        id: row.id,
        tripId: row.tripId,
        displayPath: result.localPath,
        caption: row.caption,
        capturedAt: row.capturedAt,
        capturedLat: row.capturedLat,
        capturedLng: row.capturedLng,
        mediaCapturedAt: row.mediaCapturedAt,
        storagePath: remote,
      );
    }

    return TripPhotoView(
      id: row.id,
      tripId: row.tripId,
      displayPath: local,
      caption: row.caption,
      capturedAt: row.capturedAt,
      capturedLat: row.capturedLat,
      capturedLng: row.capturedLng,
      mediaCapturedAt: row.mediaCapturedAt,
      loadError: result.error,
      hasRemoteStoragePath: true,
      storagePath: remote,
    );
  }

  Future<TripPhotoView> retryPhotoLoad(String photoId) async {
    final row = await (_db.select(_db.localTripPhotos)
          ..where((p) => p.id.equals(photoId)))
        .getSingle();
    return loadPhotoAttachment(row);
  }

  Future<TripVideoView> loadVideoAttachment(LocalTripVideo row) async {
    final local = row.localPath;
    if (local != null && local.isNotEmpty && await File(local).exists()) {
      return TripVideoView(
        id: row.id,
        tripId: row.tripId,
        displayPath: local,
        caption: row.caption,
        capturedAt: row.capturedAt,
        capturedLat: row.capturedLat,
        capturedLng: row.capturedLng,
        storagePath: row.storagePath,
      );
    }

    final remote = row.storagePath;
    return TripVideoView(
      id: row.id,
      tripId: row.tripId,
      caption: row.caption,
      capturedAt: row.capturedAt,
      capturedLat: row.capturedLat,
      capturedLng: row.capturedLng,
      hasRemoteStoragePath: remote != null && remote.isNotEmpty,
      storagePath: remote,
    );
  }

  Future<TripVideoView> _cacheVideoAttachment(LocalTripVideo row) async {
    final local = row.localPath;
    if (local != null && local.isNotEmpty && await File(local).exists()) {
      return loadVideoAttachment(row);
    }

    final remote = row.storagePath;
    if (remote == null || remote.isEmpty) {
      return loadVideoAttachment(row);
    }

    final result = await CaptureStorage.cacheVideoFromStorage(
      client: _client,
      tripId: row.tripId,
      videoId: row.id,
      storagePath: remote,
    );
    if (result.isSuccess) {
      await _db.upsertTripVideo(
        LocalTripVideosCompanion(
          id: Value(row.id),
          localPath: Value(result.localPath),
        ),
      );
      return TripVideoView(
        id: row.id,
        tripId: row.tripId,
        displayPath: result.localPath,
        caption: row.caption,
        capturedAt: row.capturedAt,
        capturedLat: row.capturedLat,
        capturedLng: row.capturedLng,
        storagePath: remote,
      );
    }

    return TripVideoView(
      id: row.id,
      tripId: row.tripId,
      displayPath: local,
      caption: row.caption,
      capturedAt: row.capturedAt,
      capturedLat: row.capturedLat,
      capturedLng: row.capturedLng,
      loadError: result.error,
      hasRemoteStoragePath: true,
      storagePath: remote,
    );
  }

  Future<TripVideoView> retryVideoLoad(String videoId) async {
    final row = await (_db.select(_db.localTripVideos)
          ..where((v) => v.id.equals(videoId)))
        .getSingle();
    return _cacheVideoAttachment(row);
  }

  Future<String> addNote({
    required String tripId,
    required String title,
    required String body,
  }) async {
    debugBreadcrumb(
      'add note start',
      screen: 'capture',
      action: 'add_note',
      details: {'tripId': tripId},
    );
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be signed in to add a note');
    }

    final id = _uuid.v4();
    final capturedAt = DateTime.now().toUtc();
    final now = capturedAt;

    await _db.upsertTripNote(
      LocalTripNotesCompanion(
        id: Value(id),
        tripId: Value(tripId),
        title: Value(title.trim()),
        body: Value(body.trim()),
        capturedAt: Value(capturedAt),
        createdBy: Value(userId),
        createdAt: Value(now),
      ),
    );

    await _syncQueue.enqueue(
      kind: SyncKind.tripNoteInsert,
      payload: {
        'id': id,
        'trip_id': tripId,
        'title': title.trim(),
        'body': body.trim(),
        'captured_at': capturedAt.toIso8601String(),
        'created_by': userId,
      },
    );
    unawaited(_syncWorker.flush());

    debugBreadcrumb(
      'add note queued',
      screen: 'capture',
      action: 'add_note',
      details: {'tripId': tripId},
    );
    return id;
  }

  Future<String> addPhoto({
    required String tripId,
    required String sourcePath,
    String? caption,
  }) async {
    debugBreadcrumb(
      'add photo start',
      screen: 'capture',
      action: 'add_photo',
      details: {'tripId': tripId},
    );
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be signed in to add a photo');
    }

    final id = _uuid.v4();
    final localPath = await CaptureStorage.persistPhoto(
      tripId: tripId,
      photoId: id,
      sourcePath: sourcePath,
    );
    final mediaMetadata = await resolveCapturePhotoMetadata(
      tagCaptureLocation: _tagCaptureLocation,
      localPath: localPath,
    );
    final capturedAt = DateTime.now().toUtc();
    final now = capturedAt;

    await _db.upsertTripPhoto(
      LocalTripPhotosCompanion(
        id: Value(id),
        tripId: Value(tripId),
        localPath: Value(localPath),
        storagePath: const Value.absent(),
        caption: Value(caption?.trim()),
        capturedAt: Value(capturedAt),
        capturedLat: Value(mediaMetadata.lat),
        capturedLng: Value(mediaMetadata.lng),
        mediaCapturedAt: Value(mediaMetadata.capturedAt),
        createdBy: Value(userId),
        createdAt: Value(now),
      ),
    );

    String? storagePath;
    try {
      storagePath = await _uploadPhoto(
        userId: userId,
        tripId: tripId,
        photoId: id,
        localPath: localPath,
      );
      await _client.from('trip_photos').insert({
        'id': id,
        'trip_id': tripId,
        'storage_path': storagePath,
        'caption': caption?.trim(),
        'captured_at': capturedAt.toIso8601String(),
        'captured_lat': mediaMetadata.lat,
        'captured_lng': mediaMetadata.lng,
        'media_captured_at': mediaMetadata.capturedAt?.toIso8601String(),
        'created_by': userId,
      });
      await _db.upsertTripPhoto(
        LocalTripPhotosCompanion(
          id: Value(id),
          storagePath: Value(storagePath),
        ),
      );
      debugBreadcrumb(
        'remote photo synced',
        screen: 'capture',
        action: 'upload_photo_remote',
        details: {'tripId': tripId},
      );
    } catch (error, stackTrace) {
      // Photo stays local-only if bucket missing or offline — still on Drift.
      reportAndLog(
        error,
        stackTrace,
        screen: 'capture',
        action: 'upload_photo_remote',
        severity: ActionFailureSeverity.degraded,
        analytics: _analytics,
      );
    }

    return id;
  }

  Future<String> addVideo({
    required String tripId,
    required String sourcePath,
    String? caption,
    double? capturedLat,
    double? capturedLng,
  }) async {
    debugBreadcrumb(
      'add video start',
      screen: 'capture',
      action: 'add_video',
      details: {'tripId': tripId},
    );
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be signed in to add a video');
    }

    final id = _uuid.v4();
    final localPath = await CaptureStorage.persistVideo(
      tripId: tripId,
      videoId: id,
      sourcePath: sourcePath,
    );
    final capturedAt = DateTime.now().toUtc();
    final now = capturedAt;

    await _db.upsertTripVideo(
      LocalTripVideosCompanion(
        id: Value(id),
        tripId: Value(tripId),
        localPath: Value(localPath),
        storagePath: const Value.absent(),
        caption: Value(caption?.trim()),
        capturedAt: Value(capturedAt),
        capturedLat: Value(capturedLat),
        capturedLng: Value(capturedLng),
        createdBy: Value(userId),
        createdAt: Value(now),
      ),
    );

    String? storagePath;
    try {
      storagePath = await _uploadVideo(
        userId: userId,
        tripId: tripId,
        videoId: id,
        localPath: localPath,
      );
      await _client.from('trip_videos').insert({
        'id': id,
        'trip_id': tripId,
        'storage_path': storagePath,
        'caption': caption?.trim(),
        'captured_at': capturedAt.toIso8601String(),
        'captured_lat': capturedLat,
        'captured_lng': capturedLng,
        'created_by': userId,
      });
      await _db.upsertTripVideo(
        LocalTripVideosCompanion(
          id: Value(id),
          storagePath: Value(storagePath),
        ),
      );
      debugBreadcrumb(
        'remote video synced',
        screen: 'capture',
        action: 'upload_video_remote',
        details: {'tripId': tripId},
      );
    } catch (error, stackTrace) {
      // Video stays local-only if bucket missing, offline, or upload is too heavy.
      reportAndLog(
        error,
        stackTrace,
        screen: 'capture',
        action: 'upload_video_remote',
        severity: ActionFailureSeverity.degraded,
        analytics: _analytics,
      );
    }

    return id;
  }

  Future<String> _uploadPhoto({
    required String userId,
    required String tripId,
    required String photoId,
    required String localPath,
  }) async {
    final bytes = await File(localPath).readAsBytes();
    final ext = CaptureStorage.normalizeExt(
      localPath.contains('.') ? '.${localPath.split('.').last}' : '.jpg',
    );
    final path = StoragePaths.capturePhoto(
      userId: userId,
      tripId: tripId,
      photoId: photoId,
      ext: ext,
    );
    await _client.storage.from(_capturesBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: CaptureStorage.contentTypeForPath(localPath),
            upsert: true,
          ),
        );
    return path;
  }

  Future<String> _uploadVideo({
    required String userId,
    required String tripId,
    required String videoId,
    required String localPath,
  }) async {
    final ext = CaptureStorage.normalizeVideoExt(
      localPath.contains('.') ? '.${localPath.split('.').last}' : '.mp4',
    );
    final path = StoragePaths.captureVideo(
      userId: userId,
      tripId: tripId,
      videoId: videoId,
      ext: ext,
    );
    await _client.storage.from(_capturesBucket).upload(
          path,
          File(localPath),
          fileOptions: FileOptions(
            contentType: CaptureStorage.videoContentTypeForPath(localPath),
            upsert: true,
          ),
        );
    return path;
  }

  Future<void> syncCaptureForTrips(Iterable<String> tripIds) async {
    final ids = tripIds.toList();
    if (ids.isEmpty) return;

    final noteRows = await _client
        .from('trip_notes')
        .select(
          'id, trip_id, title, body, captured_at, created_by, created_at',
        )
        .inFilter('trip_id', ids)
        .order('captured_at', ascending: false);

    for (final row in (noteRows as List).cast<Map<String, dynamic>>()) {
      await _db.upsertTripNote(
        LocalTripNotesCompanion(
          id: Value(row['id'] as String),
          tripId: Value(row['trip_id'] as String),
          title: Value(row['title'] as String),
          body: Value(row['body'] as String? ?? ''),
          capturedAt: Value(DateTime.parse(row['captured_at'] as String)),
          createdBy: Value(row['created_by'] as String),
          createdAt: Value(DateTime.parse(row['created_at'] as String)),
        ),
      );
    }

    final photoRows = await _client
        .from('trip_photos')
        .select(
          'id, trip_id, storage_path, caption, captured_at, captured_lat, captured_lng, media_captured_at, created_by, created_at',
        )
        .inFilter('trip_id', ids)
        .order('captured_at', ascending: false);

    for (final row in (photoRows as List).cast<Map<String, dynamic>>()) {
      final id = row['id'] as String;
      final existing = await (_db.select(_db.localTripPhotos)
            ..where((p) => p.id.equals(id)))
          .getSingleOrNull();

      final tripId = row['trip_id'] as String;
      final storagePath = row['storage_path'] as String;
      var localPath = existing?.localPath;
      if (localPath == null || !await File(localPath).exists()) {
        final cached = await CaptureStorage.cachePhotoFromStorage(
          client: _client,
          tripId: tripId,
          photoId: id,
          storagePath: storagePath,
        );
        localPath = cached.localPath;
      }

      await _db.upsertTripPhoto(
        LocalTripPhotosCompanion(
          id: Value(id),
          tripId: Value(tripId),
          localPath: Value(localPath),
          storagePath: Value(storagePath),
          caption: Value(row['caption'] as String?),
          capturedAt: Value(DateTime.parse(row['captured_at'] as String)),
          capturedLat: Value((row['captured_lat'] as num?)?.toDouble()),
          capturedLng: Value((row['captured_lng'] as num?)?.toDouble()),
          mediaCapturedAt: Value(
            _parseNullableDateTime(row['media_captured_at'] as String?),
          ),
          createdBy: Value(row['created_by'] as String),
          createdAt: Value(DateTime.parse(row['created_at'] as String)),
        ),
      );
    }

    final videoRows = await _client
        .from('trip_videos')
        .select(
          'id, trip_id, storage_path, caption, captured_at, captured_lat, captured_lng, created_by, created_at',
        )
        .inFilter('trip_id', ids)
        .order('captured_at', ascending: false);

    for (final row in (videoRows as List).cast<Map<String, dynamic>>()) {
      final id = row['id'] as String;
      final existing = await (_db.select(_db.localTripVideos)
            ..where((v) => v.id.equals(id)))
          .getSingleOrNull();

      final tripId = row['trip_id'] as String;
      final storagePath = row['storage_path'] as String;
      var localPath = existing?.localPath;
      if (localPath != null && !await File(localPath).exists()) {
        localPath = null;
      }

      await _db.upsertTripVideo(
        LocalTripVideosCompanion(
          id: Value(id),
          tripId: Value(tripId),
          localPath: Value(localPath),
          storagePath: Value(storagePath),
          caption: Value(row['caption'] as String?),
          capturedAt: Value(DateTime.parse(row['captured_at'] as String)),
          capturedLat: Value((row['captured_lat'] as num?)?.toDouble()),
          capturedLng: Value((row['captured_lng'] as num?)?.toDouble()),
          createdBy: Value(row['created_by'] as String),
          createdAt: Value(DateTime.parse(row['created_at'] as String)),
        ),
      );
    }
  }

  DateTime? _parseNullableDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.parse(raw);
  }
}
