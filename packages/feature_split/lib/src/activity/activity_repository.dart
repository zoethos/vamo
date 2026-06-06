import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'activity_models.dart';

final activityFeedProvider = StreamProvider<List<ActivityItem>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return _activityFeedStream(db);
});

Stream<List<ActivityItem>> _activityFeedStream(AppDatabase db) async* {
  yield await _buildFeed(db);
  final refresh = StreamController<void>.broadcast();
  final subs = <StreamSubscription<dynamic>>[
    db.watchAllExpenses().listen((_) => refresh.add(null)),
    db.watchAllSettlements().listen((_) => refresh.add(null)),
    db.watchAllTrips().listen((_) => refresh.add(null)),
    db.select(db.localPlanItems).watch().listen((_) => refresh.add(null)),
    db.select(db.localPlanItemRsvps).watch().listen((_) => refresh.add(null)),
  ];
  try {
    await for (final _ in refresh.stream) {
      yield await _buildFeed(db);
    }
  } finally {
    for (final s in subs) {
      await s.cancel();
    }
    await refresh.close();
  }
}

Future<List<ActivityItem>> _buildFeed(AppDatabase db) async {
  final trips = await db.select(db.localTrips).get();
  final tripNames = {for (final t in trips) t.id: t.name};

  final items = <ActivityItem>[];

  final expenses = await db.select(db.localExpenses).get();
  for (final e in expenses) {
    items.add(
      ActivityItem(
        id: 'expense_${e.id}',
        tripId: e.tripId,
        tripName: tripNames[e.tripId] ?? 'Trip',
        kind: ActivityKind.expense,
        title: e.description,
        subtitle: 'Expense added',
        occurredAt: e.createdAt,
      ),
    );
  }

  final settlements = await db.select(db.localSettlements).get();
  for (final s in settlements) {
    items.add(
      ActivityItem(
        id: 'settlement_${s.id}',
        tripId: s.tripId,
        tripName: tripNames[s.tripId] ?? 'Trip',
        kind: ActivityKind.settlement,
        title: 'Settlement ${s.status}',
        subtitle: '${s.amountCents / 100} ${s.currency}',
        occurredAt: s.createdAt,
      ),
    );
  }

  final planItems = await db.select(db.localPlanItems).get();
  final planById = {for (final p in planItems) p.id: p};
  for (final p in planItems) {
    if (p.kind != 'activity') continue;
    items.add(
      ActivityItem(
        id: 'event_created_${p.id}',
        tripId: p.tripId,
        tripName: tripNames[p.tripId] ?? 'Trip',
        kind: ActivityKind.eventCreated,
        title: p.title,
        subtitle: 'Event added',
        occurredAt: p.createdAt,
      ),
    );
  }

  final rsvps = await db.select(db.localPlanItemRsvps).get();
  for (final r in rsvps) {
    final plan = planById[r.planItemId];
    if (plan == null || plan.kind != 'activity') continue;
    items.add(
      ActivityItem(
        id: 'event_rsvp_${r.id}_${r.respondedAt.millisecondsSinceEpoch}',
        tripId: plan.tripId,
        tripName: tripNames[plan.tripId] ?? 'Trip',
        kind: ActivityKind.eventRsvp,
        title: plan.title,
        subtitle: r.status,
        occurredAt: r.respondedAt,
        rsvpStatus: r.status,
      ),
    );
  }

  items.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  return items;
}

/// Groups [items] by calendar day for section headers.
Map<DateTime, List<ActivityItem>> groupActivityByDay(List<ActivityItem> items) {
  final map = <DateTime, List<ActivityItem>>{};
  for (final item in items) {
    final day = DateTime.utc(
      item.occurredAt.year,
      item.occurredAt.month,
      item.occurredAt.day,
    );
    map.putIfAbsent(day, () => []).add(item);
  }
  return map;
}
