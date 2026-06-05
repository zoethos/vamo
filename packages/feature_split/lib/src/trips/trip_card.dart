import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../balances/balances_providers.dart';
import '../snapshot/snapshot_themes.dart';
import 'trip_format.dart';
import 'trips_models.dart';

enum TripBalanceChipState { owed, settled, allSettled }

class TripCard extends ConsumerWidget {
  const TripCard({super.key, required this.trip});

  final TripSummary trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = SnapshotThemes.resolve(
      destination: trip.destination,
      tripName: trip.name,
    );
    final media = ref.watch(tripMediaCountsProvider(trip.id));
    final balanceChip = ref.watch(tripBalanceChipProvider(trip.id));
    final dates = formatTripDateRange(trip.startDate, trip.endDate);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.push(AppRoutes.trip(trip.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 120,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: theme.gradient,
                  ),
                ),
                child: Align(
                  alignment: AlignmentDirectional.bottomStart,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(12),
                    child: Text(
                      trip.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (trip.destination != null)
                    Text(
                      trip.destination!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.graphite,
                          ),
                    ),
                  if (dates != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      dates,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.graphite,
                          ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Builder(
                    builder: (context) {
                      final mediaChips = media.when(
                        data: (c) => <Widget>[
                          _StatChip(
                            icon: Icons.photo_outlined,
                            label: '${c.photos}',
                          ),
                          _StatChip(
                            icon: Icons.sticky_note_2_outlined,
                            label: '${c.notes}',
                          ),
                          _StatChip(
                            icon: Icons.receipt_outlined,
                            label: '${c.receipts}',
                          ),
                        ],
                        loading: () => <Widget>[],
                        error: (_, __) => <Widget>[],
                      );
                      final balanceWidgets = balanceChip.when(
                        data: (chip) => <Widget>[
                          _BalanceChip(state: chip.state, label: chip.label),
                        ],
                        loading: () => <Widget>[],
                        error: (_, __) => <Widget>[],
                      );
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [...mediaChips, ...balanceWidgets],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TripBalanceChipData {
  const TripBalanceChipData({required this.state, required this.label});

  final TripBalanceChipState state;
  final String label;
}

final tripMediaCountsProvider =
    FutureProvider.family<({int photos, int notes, int receipts}), String>(
        (ref, tripId) {
  return ref.watch(appDatabaseProvider).countTripMedia(tripId);
});

final tripBalanceChipProvider =
    Provider.family<AsyncValue<TripBalanceChipData>, String>((ref, tripId) {
  final balances = ref.watch(tripNetBalancesProvider(tripId));
  final userId = ref.watch(currentUserProvider)?.id;

  return balances.when(
    loading: () => const AsyncValue.loading(),
    error: AsyncValue.error,
    data: (data) {
      if (userId == null) {
        return const AsyncValue.data(
          TripBalanceChipData(
            state: TripBalanceChipState.allSettled,
            label: 'All settled',
          ),
        );
      }
      final net = data.nets[userId] ?? 0;
      if (net == 0 && data.nets.values.every((v) => v == 0)) {
        return const AsyncValue.data(
          TripBalanceChipData(
            state: TripBalanceChipState.allSettled,
            label: 'All settled',
          ),
        );
      }
      if (net == 0) {
        return const AsyncValue.data(
          TripBalanceChipData(
            state: TripBalanceChipState.settled,
            label: 'Settled',
          ),
        );
      }
      final owed = net < 0;
      final cents = net.abs();
      final amount = (cents / 100).toStringAsFixed(2);
      return AsyncValue.data(
        TripBalanceChipData(
          state: TripBalanceChipState.owed,
          label: owed ? 'Owe $amount' : 'Owed $amount',
        ),
      );
    },
  );
});

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16, color: AppColors.jadeTeal),
      label: Text(label),
      backgroundColor: AppColors.blush,
      side: BorderSide.none,
    );
  }
}

class _BalanceChip extends StatelessWidget {
  const _BalanceChip({required this.state, required this.label});

  final TripBalanceChipState state;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (state) {
      TripBalanceChipState.owed => (AppColors.coralText.withValues(alpha: 0.12), AppColors.coralText),
      TripBalanceChipState.settled => (AppColors.blush, AppColors.jadeTeal),
      TripBalanceChipState.allSettled => (AppColors.goLime, AppColors.ink),
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
      backgroundColor: bg,
      side: BorderSide.none,
    );
  }
}
