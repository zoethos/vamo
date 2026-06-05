import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final pushDevicesRepositoryProvider = Provider<PushDevicesRepository>((ref) {
  return PushDevicesRepository(
    client: ref.watch(supabaseClientProvider),
  );
});

/// Upserts FCM tokens via `register_push_device` RPC (migration 0013).
class PushDevicesRepository {
  PushDevicesRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<void> registerToken(String fcmToken, {String platform = 'android'}) async {
    if (_client.auth.currentUser?.id == null) return;
    if (fcmToken.trim().isEmpty) return;
    await _client.rpc('register_push_device', params: {
      'p_fcm_token': fcmToken.trim(),
      'p_platform': platform,
    });
  }
}
