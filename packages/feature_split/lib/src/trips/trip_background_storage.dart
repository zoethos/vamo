import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../capture/capture_storage.dart';

/// Local + remote hero backgrounds — separate from capture photos (S44).
abstract final class TripBackgroundStorage {
  static const root = 'trip-backgrounds';

  static Future<String> persist({
    required String tripId,
    required String sourcePath,
  }) async {
    final folder = await _tripFolder(tripId);
    final ext = CaptureStorage.normalizeExt(p.extension(sourcePath));
    final dest = p.join(folder.path, 'hero$ext');
    await File(sourcePath).copy(dest);
    return dest;
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
        final dest = p.join(folder.path, 'hero$ext');
        await File(dest).writeAsBytes(bytes);
        return dest;
      },
    );
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
