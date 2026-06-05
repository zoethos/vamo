import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'trips_models.dart';
import 'trips_repository.dart';

/// Re-sync remote → Drift when auth changes or the list screen asks.
final tripsSyncProvider = FutureProvider<void>((ref) async {
  ref.watch(authStateChangesProvider);
  await ref.watch(syncCoordinatorProvider).syncNow();
});

/// UI source of truth: Drift stream. Invalidates when [tripsSyncProvider] completes.
final tripsListProvider = StreamProvider<List<TripSummary>>((ref) {
  ref.watch(authStateChangesProvider);
  ref.watch(tripsSyncProvider);
  return ref.watch(tripsRepositoryProvider).watchTripSummaries();
});

final tripDetailProvider =
    StreamProvider.family<TripDetail?, String>((ref, tripId) {
  return ref.watch(tripsRepositoryProvider).watchTrip(tripId);
});

final tripMemberCountProvider =
    StreamProvider.family<int, String>((ref, tripId) {
  return ref.watch(tripsRepositoryProvider).watchActiveMemberCount(tripId);
});

final tripMyMemberProvider =
    StreamProvider.family<LocalTripMember?, String>((ref, tripId) {
  final userId = ref.watch(authRepositoryProvider).currentUser?.id;
  if (userId == null) return Stream.value(null);
  return ref.watch(tripsRepositoryProvider).watchMember(tripId, userId);
});

final tripHasCloseObjectionProvider =
    StreamProvider.family<bool, String>((ref, tripId) {
  return ref.watch(tripsRepositoryProvider).watchTripHasCloseObjection(tripId);
});
