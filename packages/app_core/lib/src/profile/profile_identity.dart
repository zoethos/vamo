const kPlaceholderDisplayName = 'Vamigo';

String normalizeDisplayName(String value) => value.trim();

bool isPlaceholderDisplayName(String value) {
  return normalizeDisplayName(value) == kPlaceholderDisplayName;
}

bool isUsableDisplayName(String value) {
  final trimmed = normalizeDisplayName(value);
  return trimmed.isNotEmpty && trimmed != kPlaceholderDisplayName;
}

bool profileNeedsIdentityCompletion({
  required String displayName,
  required DateTime? displayNameSetAt,
}) {
  return displayNameSetAt == null || !isUsableDisplayName(displayName);
}

String shortUserId(String userId) {
  final trimmed = userId.trim();
  if (trimmed.length <= 4) return trimmed;
  return trimmed.substring(trimmed.length - 4);
}

String fallbackMemberDisplayName({
  required String userId,
  String? displayName,
  String prefix = 'Member',
}) {
  final trimmed = displayName?.trim();
  if (trimmed != null && isUsableDisplayName(trimmed)) return trimmed;
  final suffix = shortUserId(userId);
  return suffix.isEmpty ? prefix : '$prefix $suffix';
}

/// Up to two initials for avatar fallback — null when no usable display name.
String? avatarInitialsFromDisplayName(String? displayName) {
  final trimmed = displayName?.trim();
  if (trimmed == null || trimmed.isEmpty || isPlaceholderDisplayName(trimmed)) {
    return null;
  }
  final parts = trimmed
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return null;
  if (parts.length == 1) {
    final word = parts.first;
    if (word.length >= 2) {
      return word.substring(0, 2).toUpperCase();
    }
    return word[0].toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

String normalizeAvatarInitials(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
}

bool isUsableAvatarInitials(String value) {
  final normalized = normalizeAvatarInitials(value);
  return normalized.isNotEmpty && normalized.length <= 4;
}

String? preferredAvatarInitials({
  required String? preferredInitials,
  required String? displayName,
}) {
  final normalized = preferredInitials == null
      ? ''
      : normalizeAvatarInitials(preferredInitials);
  if (normalized.isNotEmpty && normalized.length <= 4) return normalized;
  return avatarInitialsFromDisplayName(displayName);
}
