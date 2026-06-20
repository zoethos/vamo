import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed access to runtime configuration loaded from `.env`.
///
/// Call [Env.load] once during bootstrap, before reading any value.
class Env {
  const Env._();

  static Future<void> load() => dotenv.load(fileName: '.env');

  static String get supabaseUrl => _require('SUPABASE_URL');
  static String get supabaseAnonKey => _require('SUPABASE_ANON_KEY');

  static String get posthogApiKey => _optional('POSTHOG_API_KEY') ?? '';

  /// PostHog ingest host (default EU cloud).
  static String get posthogHost =>
      _optional('POSTHOG_HOST') ?? 'https://eu.i.posthog.com';
  static String get fxRatesFunctionUrl =>
      _optional('FX_RATES_FUNCTION_URL') ?? '';

  /// Free key from https://exchangerate.host — required for direct client FX fallback.
  static String get exchangerateAccessKey =>
      _optional('EXCHANGERATE_ACCESS_KEY') ?? '';

  static String _require(String key) {
    final value = _optional(key);
    if (value == null || value.isEmpty) {
      throw StateError(
        'Missing required env var "$key". Copy .env.example to .env and fill it in.',
      );
    }
    return value;
  }

  static String? _optional(String key) {
    try {
      return dotenv.maybeGet(key);
    } on NotInitializedError {
      return null;
    }
  }
}
