import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../plan/plan_models.dart';
import 'activity_models.dart';

final activityFeedProvider = StreamProvider<List<ActivityItem>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final currentUserId = ref.watch(currentUserProvider)?.id;
  return _activityFeedStream(db, currentUserId: currentUserId);
});

Stream<List<ActivityItem>> _activityFeedStream(
  AppDatabase db, {
  required String? currentUserId,
}) async* {
  yield await _buildFeed(db, currentUserId: currentUserId);
  final refresh = StreamController<void>.broadcast();
  final subs = <StreamSubscription<dynamic>>[
    db.watchAllExpenses().listen((_) => refresh.add(null)),
    db.watchAllSettlements().listen((_) => refresh.add(null)),
    db.watchAllTrips().listen((_) => refresh.add(null)),
    db.select(db.localTripMembers).watch().listen((_) => refresh.add(null)),
    db.select(db.localExpenseShares).watch().listen((_) => refresh.add(null)),
    db.select(db.localPlanItems).watch().listen((_) => refresh.add(null)),
    db.select(db.localPlanItemRsvps).watch().listen((_) => refresh.add(null)),
    db.select(db.localTripNotes).watch().listen((_) => refresh.add(null)),
    db.select(db.localTripPhotos).watch().listen((_) => refresh.add(null)),
    db.select(db.localTripVideos).watch().listen((_) => refresh.add(null)),
  ];
  try {
    await for (final _ in refresh.stream) {
      yield await _buildFeed(db, currentUserId: currentUserId);
    }
  } finally {
    for (final s in subs) {
      await s.cancel();
    }
    await refresh.close();
  }
}

@visibleForTesting
Future<List<ActivityItem>> buildActivityFeedForTest(
  AppDatabase db, {
  String? currentUserId,
}) {
  return _buildFeed(db, currentUserId: currentUserId);
}

Future<List<ActivityItem>> _buildFeed(
  AppDatabase db, {
  required String? currentUserId,
}) async {
  final trips = await db.select(db.localTrips).get();
  final tripsById = {for (final t in trips) t.id: t};
  final members = await db.select(db.localTripMembers).get();
  final memberByTripUser = {
    for (final m in members) _memberKey(m.tripId, m.userId): m,
  };
  final expenseShares = await db.select(db.localExpenseShares).get();
  final sharesByExpense = <String, List<LocalExpenseShare>>{};
  for (final share in expenseShares) {
    sharesByExpense.putIfAbsent(share.expenseId, () => []).add(share);
  }

  final items = <ActivityItem>[];

  for (final member in members) {
    final joinedAt = member.joinedAt;
    if (joinedAt == null ||
        member.role == 'owner' ||
        member.status != 'active') {
      continue;
    }
    final trip = tripsById[member.tripId];
    final actor = _actorFor(
      tripId: member.tripId,
      userId: member.userId,
      currentUserId: currentUserId,
      memberByTripUser: memberByTripUser,
    );
    items.add(
      ActivityItem(
        id: 'member_joined_${member.tripId}_${member.userId}',
        tripId: member.tripId,
        tripName: trip?.name ?? 'Trip',
        tripImagePath: _tripImagePath(trip),
        kind: ActivityKind.memberJoined,
        filter: ActivityFilter.members,
        title: '${actor.name} joined',
        occurredAt: joinedAt,
        route: AppRoutes.tripMembers(member.tripId),
        actorName: actor.name,
        actorAvatarUrl: actor.avatarUrl,
        actorAvatarDisplayMode: actor.avatarDisplayMode,
        actorAvatarInitials: actor.avatarInitials,
      ),
    );
  }

  final expenses = await db.select(db.localExpenses).get();
  for (final e in expenses) {
    if (e.status == 'cancelled') continue;
    final trip = tripsById[e.tripId];
    final actor = _actorFor(
      tripId: e.tripId,
      userId: e.createdBy,
      currentUserId: currentUserId,
      memberByTripUser: memberByTripUser,
    );
    final amount = _expenseAmountForCurrentUser(
      expense: e,
      shares: sharesByExpense[e.id] ?? const [],
      currentUserId: currentUserId,
    );
    items.add(
      ActivityItem(
        id: 'expense_${e.id}',
        tripId: e.tripId,
        tripName: trip?.name ?? 'Trip',
        tripImagePath: _tripImagePath(trip),
        kind: ActivityKind.expenseAdded,
        filter: ActivityFilter.money,
        title: '${actor.name} added ${e.description}',
        occurredAt: e.createdAt,
        route: AppRoutes.tripExpenses(e.tripId),
        actorName: actor.name,
        actorAvatarUrl: actor.avatarUrl,
        actorAvatarDisplayMode: actor.avatarDisplayMode,
        actorAvatarInitials: actor.avatarInitials,
        expenseCategory: e.category,
        amountCents: amount?.cents,
        currency: amount?.currency,
        amountTone: amount?.tone ?? ActivityAmountTone.neutral,
      ),
    );
  }

  final settlements = await db.select(db.localSettlements).get();
  for (final s in settlements) {
    final trip = tripsById[s.tripId];
    final actor = _actorFor(
      tripId: s.tripId,
      userId: s.fromUser,
      currentUserId: currentUserId,
      memberByTripUser: memberByTripUser,
    );
    final amountTone = s.toUser == currentUserId
        ? ActivityAmountTone.positive
        : s.fromUser == currentUserId
            ? ActivityAmountTone.negative
            : ActivityAmountTone.neutral;
    final target = _actorFor(
      tripId: s.tripId,
      userId: s.toUser,
      currentUserId: currentUserId,
      memberByTripUser: memberByTripUser,
    );
    items.add(
      ActivityItem(
        id: 'settlement_${s.id}',
        tripId: s.tripId,
        tripName: trip?.name ?? 'Trip',
        tripImagePath: _tripImagePath(trip),
        kind: ActivityKind.settlement,
        filter: ActivityFilter.money,
        title: '${actor.name} → ${_targetName(target)}',
        occurredAt: s.createdAt,
        route: AppRoutes.tripBalances(s.tripId),
        actorName: actor.name,
        actorAvatarUrl: actor.avatarUrl,
        actorAvatarDisplayMode: actor.avatarDisplayMode,
        actorAvatarInitials: actor.avatarInitials,
        amountCents: s.amountCents,
        currency: s.currency,
        amountTone: amountTone,
      ),
    );
  }

  final planItems = await db.select(db.localPlanItems).get();
  final planById = {for (final p in planItems) p.id: p};
  for (final p in planItems) {
    final trip = tripsById[p.tripId];
    final kind = PlanItemKind.parse(p.kind);
    final actor = _actorFor(
      tripId: p.tripId,
      userId: p.createdBy,
      currentUserId: currentUserId,
      memberByTripUser: memberByTripUser,
    );
    items.add(
      ActivityItem(
        id: 'plan_item_${p.id}',
        tripId: p.tripId,
        tripName: trip?.name ?? 'Trip',
        tripImagePath: _tripImagePath(trip),
        kind: ActivityKind.planItemAdded,
        filter: ActivityFilter.plan,
        title:
            '${actor.name} added ${_planKindArticle(kind)} ${_planKindLabel(kind)} · ${p.title}',
        occurredAt: p.createdAt,
        route: AppRoutes.tripPlan(p.tripId),
        actorName: actor.name,
        actorAvatarUrl: actor.avatarUrl,
        actorAvatarDisplayMode: actor.avatarDisplayMode,
        actorAvatarInitials: actor.avatarInitials,
        planKind: kind.name,
      ),
    );
  }

  final rsvps = await db.select(db.localPlanItemRsvps).get();
  for (final r in rsvps) {
    final plan = planById[r.planItemId];
    if (plan == null) continue;
    final trip = tripsById[plan.tripId];
    final actor = _actorFor(
      tripId: plan.tripId,
      userId: r.userId,
      currentUserId: currentUserId,
      memberByTripUser: memberByTripUser,
    );
    final verb = actor.isCurrentUser ? 'are' : 'is';
    final status = _rsvpStatusLabel(r.status);
    items.add(
      ActivityItem(
        id: 'plan_rsvp_${r.id}_${r.respondedAt.millisecondsSinceEpoch}',
        tripId: plan.tripId,
        tripName: trip?.name ?? 'Trip',
        tripImagePath: _tripImagePath(trip),
        kind: ActivityKind.planRsvp,
        filter: ActivityFilter.plan,
        title: '${actor.name} $verb $status to ${plan.title}',
        occurredAt: r.respondedAt,
        route: AppRoutes.tripPlan(plan.tripId),
        actorName: actor.name,
        actorAvatarUrl: actor.avatarUrl,
        actorAvatarDisplayMode: actor.avatarDisplayMode,
        actorAvatarInitials: actor.avatarInitials,
        planKind: PlanItemKind.parse(plan.kind).name,
        rsvpStatus: r.status,
      ),
    );
  }

  final notes = await db.select(db.localTripNotes).get();
  for (final note in notes) {
    final trip = tripsById[note.tripId];
    final actor = _actorFor(
      tripId: note.tripId,
      userId: note.createdBy,
      currentUserId: currentUserId,
      memberByTripUser: memberByTripUser,
    );
    items.add(
      ActivityItem(
        id: 'note_${note.id}',
        tripId: note.tripId,
        tripName: trip?.name ?? 'Trip',
        tripImagePath: _tripImagePath(trip),
        kind: ActivityKind.noteAdded,
        filter: ActivityFilter.media,
        title:
            '${actor.name} added ${note.title.isEmpty ? 'a note' : note.title}',
        occurredAt: note.createdAt,
        route: AppRoutes.tripMemories(note.tripId),
        actorName: actor.name,
        actorAvatarUrl: actor.avatarUrl,
        actorAvatarDisplayMode: actor.avatarDisplayMode,
        actorAvatarInitials: actor.avatarInitials,
      ),
    );
  }

  final photos = await db.select(db.localTripPhotos).get();
  for (final group in _groupPhotos(photos)) {
    final trip = tripsById[group.tripId];
    final actor = _actorFor(
      tripId: group.tripId,
      userId: group.actorId,
      currentUserId: currentUserId,
      memberByTripUser: memberByTripUser,
    );
    items.add(
      ActivityItem(
        id: 'photos_${group.tripId}_${group.actorId}_${group.dayKey}',
        tripId: group.tripId,
        tripName: trip?.name ?? 'Trip',
        tripImagePath: _tripImagePath(trip),
        kind: ActivityKind.photosAdded,
        filter: ActivityFilter.media,
        title: '${actor.name} added ${group.count} '
            '${group.count == 1 ? 'photo' : 'photos'}',
        occurredAt: group.occurredAt,
        route: AppRoutes.tripMemories(group.tripId),
        actorName: actor.name,
        actorAvatarUrl: actor.avatarUrl,
        actorAvatarDisplayMode: actor.avatarDisplayMode,
        actorAvatarInitials: actor.avatarInitials,
      ),
    );
  }

  final videos = await db.select(db.localTripVideos).get();
  for (final group in _groupVideos(videos)) {
    final trip = tripsById[group.tripId];
    final actor = _actorFor(
      tripId: group.tripId,
      userId: group.actorId,
      currentUserId: currentUserId,
      memberByTripUser: memberByTripUser,
    );
    items.add(
      ActivityItem(
        id: 'videos_${group.tripId}_${group.actorId}_${group.dayKey}',
        tripId: group.tripId,
        tripName: trip?.name ?? 'Trip',
        tripImagePath: _tripImagePath(trip),
        kind: ActivityKind.videosAdded,
        filter: ActivityFilter.media,
        title: '${actor.name} added ${group.count} '
            '${group.count == 1 ? 'video' : 'videos'}',
        occurredAt: group.occurredAt,
        route: AppRoutes.tripMemories(group.tripId),
        actorName: actor.name,
        actorAvatarUrl: actor.avatarUrl,
        actorAvatarDisplayMode: actor.avatarDisplayMode,
        actorAvatarInitials: actor.avatarInitials,
      ),
    );
  }

  for (final trip in trips) {
    if (trip.closeRequestedAt != null) {
      final actor = _actorFor(
        tripId: trip.id,
        userId: trip.ownerId,
        currentUserId: currentUserId,
        memberByTripUser: memberByTripUser,
      );
      items.add(
        ActivityItem(
          id: 'trip_closing_${trip.id}',
          tripId: trip.id,
          tripName: trip.name,
          tripImagePath: _tripImagePath(trip),
          kind: ActivityKind.lifecycle,
          filter: ActivityFilter.members,
          title: '${actor.name} closing ${trip.name}',
          occurredAt: trip.closeRequestedAt!,
          route: AppRoutes.tripCloseReport(trip.id),
          actorName: actor.name,
          actorAvatarUrl: actor.avatarUrl,
          actorAvatarDisplayMode: actor.avatarDisplayMode,
          actorAvatarInitials: actor.avatarInitials,
        ),
      );
    }
    if (trip.lifecycle == 'closed') {
      final actor = _actorFor(
        tripId: trip.id,
        userId: trip.ownerId,
        currentUserId: currentUserId,
        memberByTripUser: memberByTripUser,
      );
      items.add(
        ActivityItem(
          id: 'trip_closed_${trip.id}',
          tripId: trip.id,
          tripName: trip.name,
          tripImagePath: _tripImagePath(trip),
          kind: ActivityKind.lifecycle,
          filter: ActivityFilter.members,
          title: '${trip.name} closed',
          occurredAt: trip.updatedAt,
          route: AppRoutes.tripCloseReport(trip.id),
          actorName: actor.name,
          actorAvatarUrl: actor.avatarUrl,
          actorAvatarDisplayMode: actor.avatarDisplayMode,
          actorAvatarInitials: actor.avatarInitials,
        ),
      );
    }
  }

  items.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  return items;
}

/// Groups [items] by calendar day for section headers.
Map<DateTime, List<ActivityItem>> groupActivityByDay(List<ActivityItem> items) {
  final map = <DateTime, List<ActivityItem>>{};
  for (final item in items) {
    final local = item.occurredAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    map.putIfAbsent(day, () => []).add(item);
  }
  return map;
}

String _memberKey(String tripId, String userId) => '$tripId::$userId';

String? _tripImagePath(LocalTrip? trip) {
  if (trip == null) return null;
  final local = trip.backgroundLocalPath;
  if (local != null && local.isNotEmpty) return local;
  final remote = trip.backgroundPath;
  if (remote != null && remote.startsWith('http')) return remote;
  return null;
}

_Actor _actorFor({
  required String tripId,
  required String? userId,
  required String? currentUserId,
  required Map<String, LocalTripMember> memberByTripUser,
}) {
  final member =
      userId == null ? null : memberByTripUser[_memberKey(tripId, userId)];
  final isCurrentUser = userId != null && userId == currentUserId;
  return _Actor(
    name: isCurrentUser ? 'You' : member?.displayName ?? 'Someone',
    isCurrentUser: isCurrentUser,
    avatarUrl: member?.avatarUrl,
    avatarDisplayMode: AvatarDisplayMode.parse(member?.avatarDisplayMode),
    avatarInitials: member?.avatarInitials,
  );
}

_ActivityAmount? _expenseAmountForCurrentUser({
  required LocalExpense expense,
  required List<LocalExpenseShare> shares,
  required String? currentUserId,
}) {
  if (currentUserId == null) return null;
  if (expense.payerId == currentUserId) {
    final owed = shares
        .where((s) => s.userId != currentUserId)
        .fold<int>(0, (total, s) => total + s.shareCents);
    if (owed <= 0) return null;
    return _ActivityAmount(
      cents: owed,
      currency: expense.currency,
      tone: ActivityAmountTone.positive,
    );
  }
  for (final share in shares) {
    if (share.userId == currentUserId && share.shareCents > 0) {
      return _ActivityAmount(
        cents: share.shareCents,
        currency: expense.currency,
        tone: ActivityAmountTone.negative,
      );
    }
  }
  return null;
}

String _targetName(_Actor actor) => actor.isCurrentUser ? 'you' : actor.name;

Iterable<_MediaGroup> _groupPhotos(List<LocalTripPhoto> photos) {
  final groups = <String, _MediaGroup>{};
  for (final photo in photos) {
    final actorId = photo.createdBy;
    final day = _dayKey(photo.createdAt);
    final key = '${photo.tripId}::$actorId::$day';
    groups[key] = (groups[key] ?? _MediaGroup.empty(photo.tripId, actorId, day))
        .add(photo.createdAt);
  }
  return groups.values;
}

Iterable<_MediaGroup> _groupVideos(List<LocalTripVideo> videos) {
  final groups = <String, _MediaGroup>{};
  for (final video in videos) {
    final actorId = video.createdBy;
    final day = _dayKey(video.createdAt);
    final key = '${video.tripId}::$actorId::$day';
    groups[key] = (groups[key] ?? _MediaGroup.empty(video.tripId, actorId, day))
        .add(video.createdAt);
  }
  return groups.values;
}

String _dayKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

class _Actor {
  const _Actor({
    required this.name,
    required this.isCurrentUser,
    this.avatarUrl,
    required this.avatarDisplayMode,
    this.avatarInitials,
  });

  final String name;
  final bool isCurrentUser;
  final String? avatarUrl;
  final AvatarDisplayMode avatarDisplayMode;
  final String? avatarInitials;
}

class _ActivityAmount {
  const _ActivityAmount({
    required this.cents,
    required this.currency,
    required this.tone,
  });

  final int cents;
  final String currency;
  final ActivityAmountTone tone;
}

class _MediaGroup {
  const _MediaGroup({
    required this.tripId,
    required this.actorId,
    required this.dayKey,
    required this.count,
    required this.occurredAt,
  });

  factory _MediaGroup.empty(String tripId, String actorId, String dayKey) {
    return _MediaGroup(
      tripId: tripId,
      actorId: actorId,
      dayKey: dayKey,
      count: 0,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String tripId;
  final String actorId;
  final String dayKey;
  final int count;
  final DateTime occurredAt;

  _MediaGroup add(DateTime value) {
    return _MediaGroup(
      tripId: tripId,
      actorId: actorId,
      dayKey: dayKey,
      count: count + 1,
      occurredAt: value.isAfter(occurredAt) ? value : occurredAt,
    );
  }
}

String _planKindArticle(PlanItemKind kind) {
  return switch (kind) {
    PlanItemKind.activity => 'an',
    _ => 'a',
  };
}

String _planKindLabel(PlanItemKind kind) {
  return switch (kind) {
    PlanItemKind.visit => 'Visit',
    PlanItemKind.train => 'Train',
    PlanItemKind.flight => 'Flight',
    PlanItemKind.transfer => 'Transfer',
    PlanItemKind.lodging => 'Lodging',
    PlanItemKind.activity => 'Activity',
    PlanItemKind.other => 'Plan item',
  };
}

String _rsvpStatusLabel(String status) {
  return switch (status) {
    'going' => 'Going',
    'maybe' => 'Maybe',
    'declined' => 'Not going',
    _ => status.isEmpty
        ? 'RSVPed'
        : '${status[0].toUpperCase()}${status.substring(1)}',
  };
}
