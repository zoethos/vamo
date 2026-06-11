import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Local files under app documents — copied picks and cached remote photos.
abstract final class CaptureStorage {
  static const capturesRoot = 'captures';
  static const maxVideoBytes = 100 * 1024 * 1024;

  static Future<String> persistPhoto({
    required String tripId,
    required String photoId,
    required String sourcePath,
  }) async {
    final folder = await _tripFolder(tripId);
    final ext = normalizeExt(p.extension(sourcePath));
    final dest = p.join(folder.path, '$photoId$ext');
    await File(sourcePath).copy(dest);
    return dest;
  }

  static Future<String> persistVideo({
    required String tripId,
    required String videoId,
    required String sourcePath,
  }) async {
    await ensureVideoSizeAllowed(sourcePath);
    final folder = await _videosFolder(tripId);
    final ext = normalizeVideoExt(p.extension(sourcePath));
    final dest = p.join(folder.path, '$videoId$ext');
    await File(sourcePath).copy(dest);
    return dest;
  }

  static Future<String> persistReceipt({
    required String tripId,
    required String expenseId,
    required String sourcePath,
  }) async {
    final folder = await _receiptsFolder(tripId);
    final ext = normalizeExt(p.extension(sourcePath));
    final dest = p.join(folder.path, '$expenseId$ext');
    await File(sourcePath).copy(dest);
    return dest;
  }

  static Future<StorageAttachmentLoadResult> cachePhotoFromStorage({
    required SupabaseClient client,
    required String tripId,
    required String photoId,
    required String storagePath,
  }) {
    return StorageAttachmentLoader.downloadToCache(
      client: client,
      bucket: StoragePaths.capturesBucket,
      storagePath: storagePath,
      persistBytes: (bytes) async {
        final folder = await _tripFolder(tripId);
        final ext = normalizeExt(p.extension(storagePath));
        final dest = p.join(folder.path, '$photoId$ext');
        await File(dest).writeAsBytes(bytes);
        return dest;
      },
    );
  }

  static Future<StorageAttachmentLoadResult> cacheVideoFromStorage({
    required SupabaseClient client,
    required String tripId,
    required String videoId,
    required String storagePath,
  }) async {
    try {
      final signed = await client.storage
          .from(StoragePaths.capturesBucket)
          .createSignedUrl(storagePath, 3600);
      final httpClient = http.Client();
      try {
        final response =
            await httpClient.send(http.Request('GET', Uri.parse(signed)));
        if (response.statusCode != 200) {
          return StorageAttachmentLoadResult.failure(
            StorageException(
              'Storage download failed',
              statusCode: response.statusCode.toString(),
            ),
            hadRemoteAttachment: true,
          );
        }
        final contentLength = response.contentLength;
        if (contentLength != null && contentLength > maxVideoBytes) {
          return StorageAttachmentLoadResult.failure(
            FileSystemException(
              'Video exceeds the 100 MB cache limit',
              storagePath,
            ),
            hadRemoteAttachment: true,
          );
        }

        final folder = await _videosFolder(tripId);
        final ext = normalizeVideoExt(p.extension(storagePath));
        final dest = p.join(folder.path, '$videoId$ext');
        await response.stream.pipe(File(dest).openWrite());
        try {
          await ensureVideoSizeAllowed(dest);
        } on FileSystemException {
          await deleteLocalFileBestEffort(dest);
          rethrow;
        }
        return StorageAttachmentLoadResult.local(dest);
      } finally {
        httpClient.close();
      }
    } on StorageException catch (e) {
      return StorageAttachmentLoadResult.failure(
        e,
        hadRemoteAttachment: true,
      );
    } catch (e) {
      return StorageAttachmentLoadResult.failure(
        e,
        hadRemoteAttachment: true,
      );
    }
  }

  static Future<StorageAttachmentLoadResult> cacheReceiptFromStorage({
    required SupabaseClient client,
    required String tripId,
    required String expenseId,
    required String storagePath,
  }) {
    return StorageAttachmentLoader.downloadToCache(
      client: client,
      bucket: StoragePaths.capturesBucket,
      storagePath: storagePath,
      persistBytes: (bytes) async {
        final folder = await _receiptsFolder(tripId);
        final ext = normalizeExt(p.extension(storagePath));
        final dest = p.join(folder.path, '$expenseId$ext');
        await File(dest).writeAsBytes(bytes);
        return dest;
      },
    );
  }

  /// Best-effort local file removal — never throws.
  static Future<void> deleteLocalFileBestEffort(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'capture',
        action: 'delete_local_file',
        severity: ActionFailureSeverity.degraded,
      );
    }
  }

  static Future<void> clearAll() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(dir.path, capturesRoot));
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }

  static Future<Directory> _tripFolder(String tripId) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, capturesRoot, tripId));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  static Future<Directory> _receiptsFolder(String tripId) async {
    final trip = await _tripFolder(tripId);
    final folder = Directory(p.join(trip.path, 'receipts'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  static Future<Directory> _videosFolder(String tripId) async {
    final trip = await _tripFolder(tripId);
    final folder = Directory(p.join(trip.path, 'videos'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  static String normalizeExt(String ext) {
    final lower = ext.toLowerCase();
    if (lower.isEmpty || lower == '.') return '.jpg';
    return lower;
  }

  static String normalizeVideoExt(String ext) {
    final lower = ext.toLowerCase();
    if (lower.isEmpty || lower == '.') return '.mp4';
    return lower;
  }

  static Future<void> ensureVideoSizeAllowed(String path) async {
    final file = File(path);
    final length = await file.length();
    if (length > maxVideoBytes) {
      throw FileSystemException(
        'Video exceeds the 100 MB upload limit',
        path,
      );
    }
  }

  static String videoContentTypeForPath(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.mp4':
      case '.m4v':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.webm':
        return 'video/webm';
      default:
        return 'application/octet-stream';
    }
  }

  static String contentTypeForPath(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
      case '.heif':
        return 'image/heic';
      case '.mp4':
      case '.m4v':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.webm':
        return 'video/webm';
      default:
        return 'image/jpeg';
    }
  }
}
