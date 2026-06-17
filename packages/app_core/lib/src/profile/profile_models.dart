import 'profile_identity.dart';

/// Row from `profiles` — display identity and trip base currency.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.baseCurrency,
    this.displayNameSetAt,
  });

  final String id;
  final String displayName;
  final String baseCurrency;
  final DateTime? displayNameSetAt;

  bool get needsIdentityCompletion => profileNeedsIdentityCompletion(
    displayName: displayName,
    displayNameSetAt: displayNameSetAt,
  );

  factory UserProfile.fromRow(Map<String, dynamic> row) {
    return UserProfile(
      id: row['id'] as String,
      displayName: row['display_name'] as String,
      baseCurrency: row['base_currency'] as String,
      displayNameSetAt: _nullableDate(row['display_name_set_at']),
    );
  }
}

/// Common ISO 4217 codes for profile and trip defaults.
const kProfileCurrencies = ['EUR', 'USD', 'GBP', 'CHF'];

DateTime? _nullableDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value as String)?.toUtc();
}
