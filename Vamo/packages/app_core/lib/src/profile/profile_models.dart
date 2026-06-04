/// Row from `profiles` — default display name and trip base currency.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.baseCurrency,
  });

  final String id;
  final String displayName;
  final String baseCurrency;

  factory UserProfile.fromRow(Map<String, dynamic> row) {
    return UserProfile(
      id: row['id'] as String,
      displayName: row['display_name'] as String,
      baseCurrency: row['base_currency'] as String,
    );
  }
}

/// Common ISO 4217 codes for profile and trip defaults.
const kProfileCurrencies = ['EUR', 'USD', 'GBP', 'CHF'];
