import 'package:app_core/app_core.dart';

/// Single row in the cross-trip Activity feed.
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.tripId,
    required this.tripName,
    this.tripImagePath,
    required this.kind,
    required this.filter,
    required this.title,
    required this.occurredAt,
    required this.route,
    required this.actorName,
    this.actorAvatarUrl,
    this.actorAvatarDisplayMode = AvatarDisplayMode.photo,
    this.actorAvatarInitials,
    this.planKind,
    this.expenseCategory,
    this.amountCents,
    this.currency,
    this.amountTone = ActivityAmountTone.neutral,
    this.rsvpStatus,
  });

  final String id;
  final String tripId;
  final String tripName;
  final String? tripImagePath;
  final ActivityKind kind;
  final ActivityFilter filter;
  final String title;
  final DateTime occurredAt;
  final String route;
  final String actorName;
  final String? actorAvatarUrl;
  final AvatarDisplayMode actorAvatarDisplayMode;
  final String? actorAvatarInitials;
  final String? planKind;
  final String? expenseCategory;
  final int? amountCents;
  final String? currency;
  final ActivityAmountTone amountTone;
  final String? rsvpStatus;

  bool get hasAmount => amountCents != null && currency != null;
}

enum ActivityKind {
  expenseAdded,
  memberJoined,
  settlement,
  planItemAdded,
  planRsvp,
  noteAdded,
  photosAdded,
  videosAdded,
  lifecycle,
}

enum ActivityFilter {
  all,
  money,
  plan,
  members,
  media,
}

enum ActivityAmountTone {
  neutral,
  positive,
  negative,
}
