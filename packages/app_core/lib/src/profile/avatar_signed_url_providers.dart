import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_providers.dart';
import 'avatar_storage.dart';

class _CachedSignedUrl {
  _CachedSignedUrl(this.url, this.expiresAt);

  final String url;
  final DateTime expiresAt;
}

/// TTL cache for avatar signed URLs — avoids re-signing on every member-row build.
class AvatarSignedUrlCache {
  final Map<String, _CachedSignedUrl> _entries = {};
  static const _cacheTtl = Duration(minutes: 50);

  Future<String?> resolve({
    required SupabaseClient client,
    required String? storagePath,
  }) async {
    if (storagePath == null || storagePath.isEmpty) return null;
    final cached = _entries[storagePath];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.url;
    }
    final url = await AvatarStorage.signedUrl(
      client: client,
      storagePath: storagePath,
    );
    if (url != null) {
      _entries[storagePath] = _CachedSignedUrl(
        url,
        DateTime.now().add(_cacheTtl),
      );
    }
    return url;
  }
}

final avatarSignedUrlCacheProvider = Provider<AvatarSignedUrlCache>(
  (ref) => AvatarSignedUrlCache(),
);

final memberAvatarPhotoUrlProvider =
    FutureProvider.family<String?, String?>((ref, storagePath) {
  if (storagePath == null || storagePath.isEmpty) {
    return null;
  }
  return ref.read(avatarSignedUrlCacheProvider).resolve(
        client: ref.watch(supabaseClientProvider),
        storagePath: storagePath,
      );
});
