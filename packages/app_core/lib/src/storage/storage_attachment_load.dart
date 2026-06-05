import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of downloading a private-bucket attachment to local cache.
class StorageAttachmentLoadResult {
  const StorageAttachmentLoadResult._({
    this.localPath,
    this.error,
    this.hadRemoteAttachment = false,
  });

  const StorageAttachmentLoadResult.local(String path)
      : this._(localPath: path, hadRemoteAttachment: false);

  const StorageAttachmentLoadResult.none()
      : this._();

  const StorageAttachmentLoadResult.failure(
    Object error, {
    required bool hadRemoteAttachment,
  }) : this._(error: error, hadRemoteAttachment: hadRemoteAttachment);

  final String? localPath;
  final Object? error;
  final bool hadRemoteAttachment;

  bool get isSuccess => error == null && localPath != null;
}

/// Signed-URL fetch for private Storage objects (captures bucket).
abstract final class StorageAttachmentLoader {
  static Future<StorageAttachmentLoadResult> downloadToCache({
    required SupabaseClient client,
    required String bucket,
    required String storagePath,
    required Future<String> Function(List<int> bytes) persistBytes,
  }) async {
    try {
      final signed = await client.storage
          .from(bucket)
          .createSignedUrl(storagePath, 3600);
      final response = await http.get(Uri.parse(signed));
      if (response.statusCode != 200) {
        return StorageAttachmentLoadResult.failure(
          StorageException(
            'Storage download failed',
            statusCode: response.statusCode.toString(),
          ),
          hadRemoteAttachment: true,
        );
      }
      final localPath = await persistBytes(response.bodyBytes);
      return StorageAttachmentLoadResult.local(localPath);
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
}
