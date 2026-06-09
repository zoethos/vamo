class NotificationLabels {
  const NotificationLabels({
    required this.inboxTitle,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.markAllRead,
    required this.unreadBadge,
    required this.typeCloseNotice,
    required this.typeCloseReminder,
    required this.typeDeemedClosed,
    required this.typeSettleNudge,
    required this.typeGeneric,
  });

  final String inboxTitle;
  final String emptyTitle;
  final String emptySubtitle;
  final String markAllRead;
  final String Function(int count) unreadBadge;
  final String typeCloseNotice;
  final String typeCloseReminder;
  final String typeDeemedClosed;
  final String typeSettleNudge;
  final String typeGeneric;
}
