/// Coarse compose target for contact invites — never logged or persisted.
enum ContactInviteTargetType {
  phone('phone'),
  email('email'),
  shareFallback('share_fallback');

  const ContactInviteTargetType(this.analyticsValue);
  final String analyticsValue;
}

/// A phone or email the user explicitly picked via the OS picker.
class ContactInviteTarget {
  const ContactInviteTarget({
    required this.targetType,
    required this.value,
    this.displayLabel,
  });

  final ContactInviteTargetType targetType;
  final String value;

  /// Local UI only — never sent to analytics or backend.
  final String? displayLabel;
}
