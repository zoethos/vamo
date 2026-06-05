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

  final members = await db.select(db.localTripMembers).get();
  for (final m in members) {
    if (m.status != 'active') continue;
    items.add(
      ActivityItem(
        id: 'member_${m.tripId}_${m.userId}',
        tripId: m.tripId,
        tripName: tripNames[m.tripId] ?? 'Trip',
        kind: ActivityKind.memberJoined,
        title: m.displayName ?? 'Vamigo',
        subtitle: 'Joined trip',
        occurredAt: DateTime.now().toUtc(),
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
