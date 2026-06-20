import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_providers.dart';
import 'avatar_storage.dart';
import 'profile_identity.dart';
import 'profile_models.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

/// Reads and updates the signed-in user's `profiles` row.
class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<UserProfile> fetchCurrent() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Not signed in');
    }
    final row = await _client
        .from('profiles')
        .select(
          'id, display_name, display_name_set_at, base_currency, avatar_url, '
          'avatar_display_mode, avatar_initials',
        )
        .eq('id', uid)
        .single();
    return UserProfile.fromRow(row);
  }

  String? oauthAvatarPreviewUrl() =>
      AvatarStorage.oauthPreviewUrl(_client.auth.currentUser);

  Future<String?> signedAvatarUrl(String? storagePath) {
    return AvatarStorage.signedUrl(client: _client, storagePath: storagePath);
  }

  Future<UserProfile> updateAvatar(String? storagePath) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('profiles').update({
      'avatar_url': storagePath,
      'avatar_display_mode': AvatarDisplayMode.photo.name,
    }).eq('id', uid);
    return fetchCurrent();
  }

  Future<UserProfile> clearAvatar() async {
    final uid = _client.auth.currentUser!.id;
    await AvatarStorage.deleteCanonicalAvatar(client: _client, userId: uid);
    await _client.from('profiles').update({
      'avatar_url': null,
      'avatar_display_mode': AvatarDisplayMode.initials.name,
    }).eq('id', uid);
    return fetchCurrent();
  }

  Future<UserProfile> useInitialsAvatar(String? initials) async {
    final uid = _client.auth.currentUser!.id;
    final normalized =
        initials == null ? '' : normalizeAvatarInitials(initials);
    await _client.from('profiles').update({
      'avatar_display_mode': AvatarDisplayMode.initials.name,
      'avatar_initials': normalized.isEmpty ? null : normalized,
    }).eq('id', uid);
    return fetchCurrent();
  }

  Future<UserProfile> usePhotoAvatar() async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('profiles').update(
        {'avatar_display_mode': AvatarDisplayMode.photo.name}).eq('id', uid);
    return fetchCurrent();
  }

  Future<UserProfile> uploadAvatarFromFile(String localPath) async {
    final uid = _client.auth.currentUser!.id;
    final bytes = await File(localPath).readAsBytes();
    final path = await AvatarStorage.uploadCanonicalAvatar(
      client: _client,
      userId: uid,
      bytes: bytes,
    );
    return updateAvatar(path);
  }

  Future<UserProfile> adoptOAuthAvatar() async {
    final uid = _client.auth.currentUser!.id;
    final path = await AvatarStorage.copyOAuthAvatarToStorage(
      client: _client,
      userId: uid,
    );
    if (path == null) {
      throw StateError('No OAuth avatar available');
    }
    return updateAvatar(path);
  }

  Future<UserProfile> update({
    required String displayName,
    required String baseCurrency,
  }) async {
    final uid = _client.auth.currentUser!.id;
    final trimmed = normalizeDisplayName(displayName);
    if (trimmed.isEmpty) {
      throw ArgumentError('Display name cannot be empty');
    }
    if (isPlaceholderDisplayName(trimmed)) {
      throw ArgumentError('Choose a display name other than Vamigo');
    }
    if (!kProfileCurrencies.contains(baseCurrency)) {
      throw ArgumentError('Unsupported currency: $baseCurrency');
    }

    await _client.from('profiles').update({
      'display_name': trimmed,
      'display_name_set_at': DateTime.now().toUtc().toIso8601String(),
      'base_currency': baseCurrency,
    }).eq('id', uid);

    return fetchCurrent();
  }
}
