import 'package:app_core/app_core.dart';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../expenses/expenses_providers.dart';
import 'trip_budget.dart';
import 'trip_fx_models.dart';
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

/// Remote-only hero cache download (when [backgroundStoragePath] exists locally).
final tripRemoteBackgroundCacheProvider =
    FutureProvider.family<String?, String>((ref, tripId) async {
  ref.watch(tripDetailProvider(tripId));
  final detail = ref.read(tripDetailProvider(tripId)).valueOrNull;
  if (detail == null) return null;

  final remote = detail.backgroundStoragePath;
  if (remote == null || remote.isEmpty) return null;

  return ref.read(tripsRepositoryProvider).ensureTripBackgroundCached(
        tripId: tripId,
        storagePath: remote,
      );
});

/// Resolved local file path for the user-set hero background, if any.
final tripHeroBackgroundProvider = Provider.family<String?, String>((ref, tripId) {
  final detail = ref.watch(tripDetailProvider(tripId)).valueOrNull;
  if (detail == null) return null;

  final local = detail.backgroundLocalPath;
  if (local != null && local.isNotEmpty && File(local).existsSync()) {
    return local;
  }

  final remote = detail.backgroundStoragePath;
  if (remote == null || remote.isEmpty) return null;

  return ref.watch(tripRemoteBackgroundCacheProvider(tripId)).valueOrNull;
});

/// My Trips card backdrop — local path from the list stream, else remote cache.
final tripCardBackgroundImageProvider =
    Provider.family<String?, String>((ref, tripId) {
  final trip = ref.watch(
    tripsListProvider.select(
      (async) => async.valueOrNull?.where((t) => t.id == tripId).firstOrNull,
    ),
  );
  if (trip == null) return null;

  final local = trip.backgroundLocalPath;
  if (local != null && local.isNotEmpty && File(local).existsSync()) {
    return local;
  }

  final remote = trip.backgroundStoragePath;
  if (remote == null || remote.isEmpty) return null;

  return ref.watch(tripRemoteBackgroundCacheProvider(tripId)).valueOrNull;
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

final tripFxRatesProvider =
    StreamProvider.family<List<TripFxRateRow>, String>((ref, tripId) {
  return ref.watch(tripsRepositoryProvider).watchTripFxRates(tripId);
});

final tripBudgetBurnDownProvider =
    Provider.family<TripBudgetBurnDown?, String>((ref, tripId) {
  final trip = ref.watch(tripDetailProvider(tripId)).valueOrNull;
  final expenses = ref.watch(tripExpensesProvider(tripId)).valueOrNull;
  if (trip == null || expenses == null) return null;
  final mode = TripBudgetMode.parse(trip.budgetMode);
  if (!mode.hasBurnDown) return null;
  return TripBudgetBurnDown.compute(
    mode: mode,
    budgetCents: trip.budgetCents,
    committedBaseCents: expenses
        .where((e) => e.status.affectsBalances)
        .map((e) => e.baseCents),
  );
});
