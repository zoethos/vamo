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
