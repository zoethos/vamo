import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../balances/balances_tab.dart';
import '../balances/balances_tab_labels.dart';
import '../expenses/expense_governance_labels.dart';
import '../sync/trip_realtime_binding.dart';
import 'trip_section_back_button.dart';
import 'trip_home_labels.dart';
import 'trips_providers.dart';

class TripBalancesScreen extends ConsumerWidget {
  const TripBalancesScreen({
    super.key,
    required this.tripId,
    required this.tripHomeLabels,
    required this.governanceLabels,
    required this.balancesLabels,
  });

  final String tripId;
  final TripHomeLabels tripHomeLabels;
  final ExpenseGovernanceLabels governanceLabels;
  final BalancesTabLabels balancesLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(tripRealtimeBindingProvider(tripId));

    final trip = ref.watch(tripDetailProvider(tripId));

    return trip.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(
          leading: TripSectionBackButton(tripId: tripId),
        ),
        body: AppErrorState(
          screen: 'trip_balances',
          message: tripHomeLabels.loadError,
          onRetry: () => ref.invalidate(tripDetailProvider(tripId)),
        ),
      ),
      data: (detail) {
        if (detail == null) {
          return Scaffold(
            appBar: AppBar(
              leading: TripSectionBackButton(tripId: tripId),
            ),
            body: AppEmptyState(
              screen: 'trip_balances',
              icon: Icons.map_outlined,
              title: tripHomeLabels.notFoundTitle,
              subtitle: tripHomeLabels.notFoundSubtitle,
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            leading: TripSectionBackButton(tripId: tripId),
            title: Text(tripHomeLabels.tabBalances),
          ),
          body: BalancesTab(
            tripId: tripId,
            governanceLabels: governanceLabels,
            labels: balancesLabels,
          ),
        );
      },
    );
  }
}
