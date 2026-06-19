import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../storage/storage_paths.dart';

/// Upload + signed-URL helpers for the private `avatars` bucket.
abstract final class AvatarStorage {
  static const maxAvatarDimension = 512;
  static const jpegQuality = 85;
  static const signedUrlTtlSeconds = 3600;

  static String? oauthPreviewUrl(User? user) {
    final metadata = user?.userMetadata;
    if (metadata == null) return null;
    final picture = metadata['picture'];
    if (picture is String && picture.isNotEmpty) return picture;
    final avatarUrl = metadata['avatar_url'];
    if (avatarUrl is String && avatarUrl.isNotEmpty) return avatarUrl;
    return null;
  }

  static String canonicalPath(String userId) =>
      StoragePaths.userAvatar(userId: userId);

  static Uint8List reencodeToCanonicalJpeg(List<int> bytes) {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) {
      throw StateError('Unsupported avatar image');
    }
    final resized = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? maxAvatarDimension : null,
      height: decoded.height > decoded.width ? maxAvatarDimension : null,
      maintainAspect: true,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: jpegQuality));
  }

  static Future<String> uploadCanonicalAvatar({
    required SupabaseClient client,
    required String userId,
    required List<int> bytes,
  }) async {
    final jpeg = reencodeToCanonicalJpeg(bytes);
    final path = canonicalPath(userId);
    await client.storage.from(StoragePaths.avatarsBucket).uploadBinary(
          path,
          jpeg,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return path;
  }

  static Future<void> deleteCanonicalAvatar({
    required SupabaseClient client,
    required String userId,
  }) async {
    final path = canonicalPath(userId);
    try {
      await client.storage.from(StoragePaths.avatarsBucket).remove([path]);
    } on StorageException catch (error) {
      if (error.statusCode != '404') rethrow;
    }
  }

  static Future<String?> signedUrl({
    required SupabaseClient client,
    required String? storagePath,
    int expiresInSeconds = signedUrlTtlSeconds,
  }) async {
    if (storagePath == null || storagePath.isEmpty) return null;
    return client.storage
        .from(StoragePaths.avatarsBucket)
        .createSignedUrl(storagePath, expiresInSeconds);
  }

  static Future<String?> copyOAuthAvatarToStorage({
    required SupabaseClient client,
    required String userId,
  }) async {
    final previewUrl = oauthPreviewUrl(client.auth.currentUser);
    if (previewUrl == null) return null;

    final response = await http.get(Uri.parse(previewUrl));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw StateError('Could not download OAuth avatar');
    }

    return uploadCanonicalAvatar(
      client: client,
      userId: userId,
      bytes: response.bodyBytes,
    );
  }
}
