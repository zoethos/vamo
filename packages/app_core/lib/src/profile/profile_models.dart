import 'profile_identity.dart';

/// Row from `profiles` — display identity and trip base currency.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.baseCurrency,
    this.displayNameSetAt,
    this.avatarUrl,
    this.avatarDisplayMode = AvatarDisplayMode.photo,
    this.avatarInitials,
  });

  final String id;
  final String displayName;
  final String baseCurrency;
  final DateTime? displayNameSetAt;

  /// Storage path in the private `avatars` bucket — never a provider hot-link.
  final String? avatarUrl;
  final AvatarDisplayMode avatarDisplayMode;
  final String? avatarInitials;

  bool get usesInitialsAvatar =>
      avatarDisplayMode == AvatarDisplayMode.initials;

  String? get activeAvatarStoragePath => usesInitialsAvatar ? null : avatarUrl;

  String? get effectiveAvatarInitials => preferredAvatarInitials(
        preferredInitials: avatarInitials,
        displayName: displayName,
      );

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
      avatarUrl: row['avatar_url'] as String?,
      avatarDisplayMode: AvatarDisplayMode.parse(
        row['avatar_display_mode'] as String?,
      ),
      avatarInitials: row['avatar_initials'] as String?,
    );
  }
}

enum AvatarDisplayMode {
  photo,
  initials;

  static AvatarDisplayMode parse(String? raw) {
    return AvatarDisplayMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => AvatarDisplayMode.photo,
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
