import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_providers.dart';

const kSuggestionCategories = ['trips', 'money', 'sharing', 'other'];

final suggestionsRepositoryProvider = Provider<SuggestionsRepository>((ref) {
  return SuggestionsRepository(ref.watch(supabaseClientProvider));
});

/// Persists feature suggestions (layer 4). Text stays in Postgres, not PostHog.
class SuggestionsRepository {
  SuggestionsRepository(this._client);

  final SupabaseClient _client;

  static Future<String> appVersionLabel() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  Future<void> submit({
    required String body,
    required String category,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');

    final trimmed = body.trim();
    if (trimmed.isEmpty || trimmed.length > 500) {
      throw ArgumentError('Suggestion must be 1–500 characters');
    }
    if (!kSuggestionCategories.contains(category)) {
      throw ArgumentError('Invalid category: $category');
    }

    await _client.from('suggestions').insert({
      'user_id': uid,
      'body': trimmed,
      'category': category,
      'app_version': await appVersionLabel(),
      'platform': defaultTargetPlatform.name,
    });
  }
}
