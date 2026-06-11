/// Captures-bucket object paths — **load-bearing** for Storage RLS.
///
/// Policies in `supabase/migrations/0005_captures_storage_policies.sql` (read)
/// and `0009_captures_write_policies.sql` (write) use
/// `storage.foldername(name)`:
///   - `[1]` = owner user id (`auth.uid()` on insert)
///   - `[2]` = trip id (`is_trip_member`)
///
/// Do not build capture/receipt paths as string literals outside this file.
abstract final class StoragePaths {
  static const capturesBucket = 'captures';

  /// `{userId}/{tripId}/{photoId}{ext}`
  static String capturePhoto({
    required String userId,
    required String tripId,
    required String photoId,
    required String ext,
  }) =>
      '$userId/$tripId/$photoId${_normalizeExt(ext)}';

  /// `{userId}/{tripId}/videos/{videoId}{ext}`
  static String captureVideo({
    required String userId,
    required String tripId,
    required String videoId,
    required String ext,
  }) =>
      '$userId/$tripId/videos/$videoId${_normalizeExt(ext)}';

  /// `{userId}/{tripId}/receipts/{expenseId}{ext}` — 4-segment receipt path.
  static String expenseReceipt({
    required String userId,
    required String tripId,
    required String expenseId,
    required String ext,
  }) =>
      '$userId/$tripId/receipts/$expenseId${_normalizeExt(ext)}';

  static const tripBackgroundsBucket = 'trip-backgrounds';

  /// `{userId}/{tripId}/background{ext}` — hero badge; not a capture photo.
  static String tripBackground({
    required String userId,
    required String tripId,
    required String ext,
  }) =>
      '$userId/$tripId/background${_normalizeExt(ext)}';

  static String _normalizeExt(String ext) {
    final lower = ext.toLowerCase();
    if (lower.isEmpty || lower == '.') return '.jpg';
    return lower.startsWith('.') ? lower : '.$lower';
  }
}
