/// How an invite was shared or accepted (R9 analytics — no token values).
enum InviteChannel {
  qr('qr'),
  link('link'),
  contact('contact');

  const InviteChannel(this.analyticsValue);
  final String analyticsValue;

  /// Parses `ch` query param; unknown or absent values default to [link].
  static InviteChannel fromQuery(String? value) {
    if (value == null || value.isEmpty) return InviteChannel.link;
    for (final channel in InviteChannel.values) {
      if (channel.analyticsValue == value) return channel;
    }
    return InviteChannel.link;
  }
}
