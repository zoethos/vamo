import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../trips/trips_providers.dart';
import 'all_expenses_providers.dart';
import 'expense_models.dart';
import 'expenses_providers.dart';
import 'trip_expense_list_tile.dart';

class ExpensesListScreenLabels {
  const ExpensesListScreenLabels({
    required this.title,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.loadError,
    required this.allTrips,
  });

  final String title;
  final String emptyTitle;
  final String emptySubtitle;
  final String loadError;
  final String allTrips;
}

/// Cross-trip expense list with receipt thumbnails and trip filter.
class ExpensesListScreen extends ConsumerStatefulWidget {
  const ExpensesListScreen({super.key, required this.labels});

  final ExpensesListScreenLabels labels;

  @override
  ConsumerState<ExpensesListScreen> createState() => _ExpensesListScreenState();
}

class _ExpensesListScreenState extends ConsumerState<ExpensesListScreen> {
  String? _tripFilter;

  @override
  Widget build(BuildContext context) {
    final expenses = ref.watch(allExpensesProvider);
    final trips = ref.watch(tripsListProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.labels.title)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          trips.when(
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
                child: Row(
                  children: [
                    FilterChip(
                      label: Text(widget.labels.allTrips),
                      selected: _tripFilter == null,
                      onSelected: (_) => setState(() => _tripFilter = null),
                    ),
                    const SizedBox(width: 8),
                    for (final t in list)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: FilterChip(
                          label: Text(t.name),
                          selected: _tripFilter == t.id,
                          onSelected: (_) =>
                              setState(() => _tripFilter = t.id),
                        ),
                      ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          Expanded(
            child: expenses.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => AppErrorState(
                screen: 'expenses',
                message: widget.labels.loadError,
                onRetry: () => ref.invalidate(allExpensesProvider),
              ),
              data: (list) {
                final filtered = _tripFilter == null
                    ? list
                    : list.where((e) => e.tripId == _tripFilter).toList();
                if (filtered.isEmpty) {
                  return AppEmptyState(
                    screen: 'expenses',
                    icon: Icons.receipt_long_outlined,
                    title: widget.labels.emptyTitle,
                    subtitle: widget.labels.emptySubtitle,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsetsDirectional.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _ExpenseRow(expense: filtered[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseRow extends ConsumerWidget {
  const _ExpenseRow({required this.expense});

  final ExpenseSummary expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripNames = ref.watch(tripNameMapProvider);
    final members = ref.watch(tripMembersForExpenseProvider(expense.tripId));
    final tripCurrency =
        ref.watch(tripsListProvider).valueOrNull
            ?.where((t) => t.id == expense.tripId)
            .map((t) => t.baseCurrency)
            .firstOrNull ??
        expense.currency;

    return members.when(
      loading: () => const Card(
        child: ListTile(title: Text('…')),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (memberList) {
        final payer = memberList
            .where((m) => m.userId == expense.payerId)
            .map((m) => m.displayName)
            .firstOrNull ??
            'Someone';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tripNames[expense.tripId] ?? 'Trip',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.graphite,
                  ),
            ),
            const SizedBox(height: 4),
            TripExpenseListTile(
              expenseId: expense.id,
              tripId: expense.tripId,
              description: expense.description,
              payer: payer,
              spentAt: expense.spentAt,
              baseCents: expense.baseCents,
              amountCents: expense.amountCents,
              tripBaseCurrency: tripCurrency,
              expenseCurrency: expense.currency,
              receiptPath: expense.receiptPath,
              localReceiptPath: expense.localReceiptPath,
            ),
          ],
        );
      },
    );
  }
}
