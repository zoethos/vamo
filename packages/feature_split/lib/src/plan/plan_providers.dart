import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_rsvp_models.dart';
import 'plan_models.dart';
import 'plan_repository.dart';

final tripPlanItemsProvider =
    StreamProvider.family<List<PlanItemSummary>, String>((ref, tripId) {
  return ref.watch(planRepositoryProvider).watchPlanItems(tripId);
});

final tripListItemsProvider =
    StreamProvider.family<List<TripListItemSummary>, String>((ref, tripId) {
  return ref.watch(planRepositoryProvider).watchListItems(tripId);
});

final tripEventRsvpsProvider =
    StreamProvider.family<List<EventRsvpRow>, String>((ref, tripId) {
  return ref.watch(planRepositoryProvider).watchEventRsvps(tripId);
});

final tripPlanEventViewsProvider =
    Provider.family<Map<String, PlanItemEventView>, String>((ref, tripId) {
  final plans = ref.watch(tripPlanItemsProvider(tripId)).valueOrNull ?? [];
  final rsvps = ref.watch(tripEventRsvpsProvider(tripId)).valueOrNull ?? [];
  final userId = ref.watch(authRepositoryProvider).currentUser?.id;
  final views = <String, PlanItemEventView>{};

  for (final item in plans) {
    if (item.kind != PlanItemKind.activity) continue;
    final itemRows = rsvps.where((r) => r.planItemId == item.id);
    views[item.id] = PlanItemEventView(
      item: item,
      counts: aggregateEventRsvpCounts(itemRows),
      myStatus: callerEventRsvpStatus(
        rows: rsvps,
        planItemId: item.id,
        userId: userId,
      ),
    );
  }
  return views;
});
