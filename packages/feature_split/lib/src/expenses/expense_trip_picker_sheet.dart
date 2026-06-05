import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../trips/trip_format.dart';
import 'expenses_overview_providers.dart';

/// Bottom sheet: pick a trip before adding an expense from the shell FAB.
Future<void> showExpenseTripPickerSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String title,
  required String lastUsedLabel,
}) {
  final trips = ref.read(expensePickerTripsProvider);

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => Consumer(
      builder: (ctx, sheetRef, _) {
        final lastUsed =
            sheetRef.watch(expensesOverviewProvider).valueOrNull?.lastUsedTripId;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 8),
                child: Text(
                  title,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              for (final trip in trips)
                ListTile(
                  leading: Icon(
                    Icons.luggage_outlined,
                    color: trip.id == lastUsed
                        ? AppColors.jadeTeal
                        : AppColors.graphite,
                  ),
                  title: Text(trip.name),
                  subtitle: Text(
                    [
                      if (trip.id == lastUsed) lastUsedLabel,
                      formatTripDateRange(trip.startDate, trip.endDate),
                    ]
                        .whereType<String>()
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.push(AppRoutes.tripAddExpense(trip.id));
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ),
  );
}

/// Routes to add-expense, skipping the picker when only one open trip exists.
void openAddExpenseFromShell({
  required BuildContext context,
  required WidgetRef ref,
  required String pickerTitle,
  required String lastUsedLabel,
}) {
  final trips = ref.read(expensePickerTripsProvider);
  if (trips.length == 1) {
    context.push(AppRoutes.tripAddExpense(trips.first.id));
    return;
  }
  showExpenseTripPickerSheet(
    context: context,
    ref: ref,
    title: pickerTitle,
    lastUsedLabel: lastUsedLabel,
  );
}
