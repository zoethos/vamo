import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../capture/capture_storage.dart';

/// Local + remote hero backgrounds — separate from capture photos (S44).
abstract final class TripBackgroundStorage {
  static const root = 'trip-backgrounds';

  /// Clears [PaintingBinding.imageCache] for a hero file so [Image.file] reloads bytes.
  static Future<void> evictHeroImageCache(String localPath) async {
    await FileImage(File(localPath)).evict();
  }

  static Future<String> persist({
    required String tripId,
    required String sourcePath,
  }) async {
    final folder = await _tripFolder(tripId);
    final ext = CaptureStorage.normalizeExt(p.extension(sourcePath));
    return _writeHeroFile(
      folder: folder,
      ext: ext,
      write: (dest) => File(sourcePath).copy(dest.path),
    );
  }

  static Future<StorageAttachmentLoadResult> cacheFromStorage({
    required SupabaseClient client,
    required String tripId,
    required String storagePath,
  }) {
    return StorageAttachmentLoader.downloadToCache(
      client: client,
      bucket: StoragePaths.tripBackgroundsBucket,
      storagePath: storagePath,
      persistBytes: (bytes) async {
        final folder = await _tripFolder(tripId);
        final ext = CaptureStorage.normalizeExt(p.extension(storagePath));
        return _writeHeroFile(
          folder: folder,
          ext: ext,
          write: (dest) => dest.writeAsBytes(bytes),
        );
      },
    );
  }

  static Future<String> _writeHeroFile({
    required Directory folder,
    required String ext,
    required Future<void> Function(File dest) write,
  }) async {
    await _removePreviousHeroFiles(folder);
    final dest = File(
      p.join(
        folder.path,
        'hero_${DateTime.now().millisecondsSinceEpoch}$ext',
      ),
    );
    await write(dest);
    await evictHeroImageCache(dest.path);
    return dest.path;
  }

  static Future<void> _removePreviousHeroFiles(Directory folder) async {
    if (!await folder.exists()) return;
    await for (final entity in folder.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('hero_') || name.startsWith('hero.')) {
        await evictHeroImageCache(entity.path);
        await entity.delete();
      }
    }
  }

  static Future<Directory> _tripFolder(String tripId) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, root, tripId));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }
}
