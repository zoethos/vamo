import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settlements_repository.dart';

final tripSettlementsProvider =
    StreamProvider.family<List<SettlementRecord>, String>((ref, tripId) {
  return ref.watch(settlementsRepositoryProvider).watchTripSettlements(tripId);
});

/// Settlements awaiting confirmation by the signed-in user (recipient).
final tripPendingConfirmationsProvider =
    Provider.family<List<SettlementRecord>, String>((ref, tripId) {
  final userId = ref.watch(currentUserProvider)?.id;
  final rows = ref.watch(tripSettlementsProvider(tripId));
  return rows.when(
    data: (list) => list
        .where(
          (s) =>
              s.awaitingConfirm &&
              s.toUserId == userId,
        )
        .toList(),
    loading: () => [],
    error: (_, __) => [],
  );
});

/// Marked settlements the signed-in user initiated, still awaiting recipient confirm.
final tripPayerAwaitingConfirmProvider =
    Provider.family<List<SettlementRecord>, String>((ref, tripId) {
  final userId = ref.watch(currentUserProvider)?.id;
  final rows = ref.watch(tripSettlementsProvider(tripId));
  return rows.when(
    data: (list) => list
        .where((s) => s.awaitingConfirm && s.fromUserId == userId)
        .toList(),
    loading: () => [],
    error: (_, __) => [],
  );
});
