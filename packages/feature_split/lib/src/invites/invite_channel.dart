/// How an invite was shared or accepted (R9 analytics — no token values).
enum InviteChannel {
  qr('qr'),
  link('link');

  const InviteChannel(this.analyticsValue);
  final String analyticsValue;
}
