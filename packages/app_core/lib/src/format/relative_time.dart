/// Relative labels for activity timestamps (S35).
///
/// Returns "Today", "Yesterday", "N days ago", or a short calendar date.
String formatRelativeTime(DateTime occurredAt, {DateTime? now}) {
  final local = occurredAt.toLocal();
  final clock = (now ?? DateTime.now()).toLocal();
  final today = DateTime(clock.year, clock.month, clock.day);
  final day = DateTime(local.year, local.month, local.day);
  final delta = today.difference(day).inDays;

  if (delta == 0) return 'Today';
  if (delta == 1) return 'Yesterday';
  if (delta > 1 && delta < 7) return '$delta days ago';
  return _shortDate(local);
}

String _shortDate(DateTime local) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[local.month - 1]} ${local.day}';
}
