import 'dart:io';

import 'package:http/http.dart' as http;
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

  /// Downloads a private-bucket object via signed URL into app documents.
  static Future<String?> cacheFromStorage({
    required SupabaseClient client,
    required String bucket,
    required String tripId,
    required String photoId,
    required String storagePath,
  }) async {
    try {
      final signed = await client.storage
          .from(bucket)
          .createSignedUrl(storagePath, 3600);
      final response = await http.get(Uri.parse(signed));
      if (response.statusCode != 200) return null;

      final folder = await _tripFolder(tripId);
      final ext = normalizeExt(p.extension(storagePath));
      final dest = p.join(folder.path, '$photoId$ext');
      await File(dest).writeAsBytes(response.bodyBytes);
      return dest;
    } catch (_) {
      return null;
    }
  }

  /// Removes all cached capture images (sign-out privacy hygiene).
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
