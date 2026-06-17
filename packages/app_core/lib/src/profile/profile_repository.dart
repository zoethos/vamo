import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_providers.dart';
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
        .select('id, display_name, display_name_set_at, base_currency')
        .eq('id', uid)
        .single();
    return UserProfile.fromRow(row);
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

    await _client
        .from('profiles')
        .update({
          'display_name': trimmed,
          'display_name_set_at': DateTime.now().toUtc().toIso8601String(),
          'base_currency': baseCurrency,
        })
        .eq('id', uid);

    return fetchCurrent();
  }
}
