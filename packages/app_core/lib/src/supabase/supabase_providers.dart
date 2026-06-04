import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The initialized Supabase client.
///
/// `Supabase.initialize(...)` must have run during bootstrap before this is
/// read. We override this provider in `main` with the live instance so tests
/// can substitute a fake.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
