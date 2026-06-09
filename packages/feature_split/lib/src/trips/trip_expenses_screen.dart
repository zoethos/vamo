import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'trip_section_back_button.dart';
import 'package:go_router/go_router.dart';

import '../expenses/expense_governance_labels.dart';
import '../sync/trip_realtime_binding.dart';
import 'trip_budget_labels.dart';
import 'trip_expenses_tab.dart';
import 'trip_home_labels.dart';
import 'trips_providers.dart';

class TripExpensesScreen extends ConsumerWidget {
  const TripExpensesScreen({
    super.key,
    required this.tripId,
    required this.tripHomeLabels,
    required this.governanceLabels,
    required this.budgetLabels,
  });

  final String tripId;
  final TripHomeLabels tripHomeLabels;
  final ExpenseGovernanceLabels governanceLabels;
  final TripBudgetLabels budgetLabels;

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
          screen: 'trip_expenses',
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
              screen: 'trip_expenses',
              icon: Icons.map_outlined,
              title: tripHomeLabels.notFoundTitle,
              subtitle: tripHomeLabels.notFoundSubtitle,
            ),
          );
        }

        final readOnly = isTripReadOnly(TripLifecycle.parse(detail.lifecycle));

        return Scaffold(
          appBar: AppBar(
            leading: TripSectionBackButton(tripId: tripId),
            title: Text(tripHomeLabels.tabExpenses),
            actions: [
              if (!readOnly)
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: tripHomeLabels.addExpense,
                  onPressed: () =>
                      context.push(AppRoutes.tripAddExpense(tripId)),
                ),
            ],
          ),
          body: TripExpensesTab(
            tripId: tripId,
            baseCurrency: detail.baseCurrency,
            readOnly: readOnly,
            governanceLabels: governanceLabels,
            budgetLabels: budgetLabels,
          ),
        );
      },
    );
  }
}
