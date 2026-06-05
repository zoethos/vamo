import 'package:flutter_riverpod/flutter_riverpod.dart';

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
