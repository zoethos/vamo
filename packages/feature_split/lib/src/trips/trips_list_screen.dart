import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../invites/invite_flow.dart';
import 'trip_card.dart';
import 'trip_format.dart';
import 'trips_models.dart';
import 'trips_providers.dart';

enum TripListFilter { all, upcoming, past, drafts }

class TripsListScreenLabels {
  const TripsListScreenLabels({
    required this.title,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.syncPendingLabel,
    required this.syncSubtitle,
    required this.filterAll,
    required this.filterUpcoming,
    required this.filterPast,
    required this.filterDrafts,
    required this.loadError,
    required this.syncError,
  });

  final String title;
  final String emptyTitle;
  final String emptySubtitle;
  final String Function(int count) syncPendingLabel;
  final String syncSubtitle;
  final String filterAll;
  final String filterUpcoming;
  final String filterPast;
  final String filterDrafts;
  final String loadError;
  final String syncError;
}

class TripsListScreen extends ConsumerStatefulWidget {
  const TripsListScreen({super.key, required this.labels});

  final TripsListScreenLabels labels;

  @override
  ConsumerState<TripsListScreen> createState() => _TripsListScreenState();
}

class _TripsListScreenState extends ConsumerState<TripsListScreen> {
  TripListFilter _filter = TripListFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.invalidate(tripsSyncProvider);
      await tryConsumePendingInvite(ref: ref, context: context);
    });
  }

  List<TripSummary> _filtered(List<TripSummary> list) {
    final now = DateTime.now();
    return switch (_filter) {
      TripListFilter.all => list,
      TripListFilter.drafts => const [],
      TripListFilter.upcoming => list.where((t) {
          final start = parseTripDate(t.startDate);
          return start != null && start.isAfter(now);
        }).toList(),
      TripListFilter.past => list.where((t) {
          final end = parseTripDate(t.endDate) ?? parseTripDate(t.startDate);
          return end != null && end.isBefore(now);
        }).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(tripsSyncProvider);
    final trips = ref.watch(tripsListProvider);
    final pendingSync = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              BrandAssets.primaryMark,
              height: 28,
              package: 'vamo',
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.labels.title)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(tripsSyncProvider),
          ),
        ],
      ),
      body: sync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorState(
          screen: 'trips_list',
          kind: AnalyticsErrorKind.network,
          message: widget.labels.syncError,
          onRetry: () => ref.invalidate(tripsSyncProvider),
        ),
        data: (_) => trips.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AppErrorState(
            screen: 'trips_list',
            message: widget.labels.loadError,
            onRetry: () => ref.invalidate(tripsListProvider),
          ),
          data: (list) {
            final filtered = _filtered(list);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      _FilterPill(
                        label: widget.labels.filterAll,
                        selected: _filter == TripListFilter.all,
                        onTap: () =>
                            setState(() => _filter = TripListFilter.all),
                      ),
                      const SizedBox(width: 8),
                      _FilterPill(
                        label: widget.labels.filterUpcoming,
                        selected: _filter == TripListFilter.upcoming,
                        onTap: () =>
                            setState(() => _filter = TripListFilter.upcoming),
                      ),
                      const SizedBox(width: 8),
                      _FilterPill(
                        label: widget.labels.filterPast,
                        selected: _filter == TripListFilter.past,
                        onTap: () =>
                            setState(() => _filter = TripListFilter.past),
                      ),
                      const SizedBox(width: 8),
                      _FilterPill(
                        label: widget.labels.filterDrafts,
                        selected: _filter == TripListFilter.drafts,
                        onTap: () =>
                            setState(() => _filter = TripListFilter.drafts),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? AppEmptyState(
                          screen: 'trips_list',
                          icon: Icons.airport_shuttle_outlined,
                          title: widget.labels.emptyTitle,
                          subtitle: widget.labels.emptySubtitle,
                          useBrandMark: true,
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            ref.invalidate(tripsSyncProvider);
                            await ref.read(tripsSyncProvider.future);
                          },
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsetsDirectional.all(16),
                            itemCount:
                                filtered.length + (pendingSync > 0 ? 1 : 0),
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) {
                              if (pendingSync > 0 && i == 0) {
                                return Material(
                                  color: AppColors.blush,
                                  borderRadius: BorderRadius.circular(12),
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.cloud_upload_outlined,
                                      color: AppColors.jadeTeal,
                                    ),
                                    title: Text(
                                      widget.labels.syncPendingLabel(pendingSync),
                                    ),
                                    subtitle: Text(widget.labels.syncSubtitle),
                                    onTap: () =>
                                        ref.invalidate(tripsSyncProvider),
                                  ),
                                );
                              }
                              final index = pendingSync > 0 ? i - 1 : i;
                              return TripCard(trip: filtered[index]);
                            },
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.goLime.withValues(alpha: 0.35),
      checkmarkColor: AppColors.ink,
    );
  }
}
