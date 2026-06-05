import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Local files under app documents — copied picks and cached remote photos.
abstract final class CaptureStorage {
  static const capturesRoot = 'captures';

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
    } catch (_) {}
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

  static String normalizeExt(String ext) {
    final lower = ext.toLowerCase();
    if (lower.isEmpty || lower == '.') return '.jpg';
    return lower;
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
      default:
        return 'image/jpeg';
    }
  }
}
