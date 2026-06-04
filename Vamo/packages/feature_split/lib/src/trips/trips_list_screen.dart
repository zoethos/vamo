import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../invites/invite_flow.dart';
import 'trip_format.dart';
import 'trips_providers.dart';

/// The home surface after sign-in. Slice 1: list reads Drift, create opens trip home.
class TripsListScreen extends ConsumerStatefulWidget {
  const TripsListScreen({super.key});

  @override
  ConsumerState<TripsListScreen> createState() => _TripsListScreenState();
}

class _TripsListScreenState extends ConsumerState<TripsListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.invalidate(tripsSyncProvider);
      await tryConsumePendingInvite(ref: ref, context: context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(tripsSyncProvider);
    final trips = ref.watch(tripsListProvider);
    final pendingSync = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your trips'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(tripsSyncProvider),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: sync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorState(
          screen: 'trips_list',
          kind: AnalyticsErrorKind.network,
          message: 'Could not sync your trips.',
          onRetry: () => ref.invalidate(tripsSyncProvider),
        ),
        data: (_) => trips.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AppErrorState(
            screen: 'trips_list',
            message: 'Could not load your trips.',
            onRetry: () => ref.invalidate(tripsListProvider),
          ),
          data: (list) => list.isEmpty
              ? const AppEmptyState(
                  screen: 'trips_list',
                  icon: Icons.airport_shuttle_outlined,
                  title: 'No trips yet',
                  subtitle: 'Tap Si va? to start one.',
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(tripsSyncProvider);
                    await ref.read(tripsSyncProvider.future);
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length + (pendingSync > 0 ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      if (pendingSync > 0 && i == 0) {
                        return Material(
                          color: AppColors.sandLight,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            leading: const Icon(Icons.cloud_upload_outlined,
                                color: AppColors.teal),
                            title: Text(
                              '$pendingSync change${pendingSync == 1 ? '' : 's'} waiting to sync',
                            ),
                            subtitle: const Text(
                              'Will upload when you are back online',
                            ),
                            onTap: () => ref.invalidate(tripsSyncProvider),
                          ),
                        );
                      }
                      final index = pendingSync > 0 ? i - 1 : i;
                      final t = list[index];
                      final dates =
                          formatTripDateRange(t.startDate, t.endDate);
                      return Card(
                        child: ListTile(
                          title: Text(t.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (t.destination != null) Text(t.destination!),
                              if (dates != null) Text(dates),
                              Text(
                                t.baseCurrency,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.muted),
                              ),
                            ],
                          ),
                          onTap: () => context.push(AppRoutes.trip(t.id)),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        onPressed: () => context.push(AppRoutes.tripCreate),
        icon: const Icon(Icons.add),
        label: const Text('Si va?'),
      ),
    );
  }
}
