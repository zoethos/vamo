import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'expense_trip_picker_sheet.dart';
import 'expenses_overview.dart';
import 'expenses_overview_providers.dart';
import 'money_format.dart';

class ExpensesListScreenLabels {
  const ExpensesListScreenLabels({
    required this.title,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.loadError,
    required this.balanceAllSettled,
    required this.balanceYouOwe,
    required this.balanceYouAreOwed,
    required this.balanceAcrossTrips,
    required this.periodThisMonth,
    required this.periodThisYear,
    required this.earlierSection,
    required this.totalSpent,
    required this.myShare,
    required this.settlementUnsettled,
    required this.settlementSettled,
    required this.settlementAllSettled,
    required this.unresolvedBadge,
    required this.pickerTitle,
    required this.pickerLastUsed,
    required this.addExpenseTooltip,
  });

  final String title;
  final String emptyTitle;
  final String emptySubtitle;
  final String loadError;
  final String balanceAllSettled;
  final String Function(String amount, int tripCount) balanceYouOwe;
  final String Function(String amount) balanceYouAreOwed;
  final String balanceAcrossTrips;
  final String periodThisMonth;
  final String periodThisYear;
  final String earlierSection;
  final String totalSpent;
  final String myShare;
  final String settlementUnsettled;
  final String settlementSettled;
  final String settlementAllSettled;
  final String unresolvedBadge;
  final String pickerTitle;
  final String pickerLastUsed;
  final String addExpenseTooltip;
}

/// Cross-trip money overview: balance header, trip rollups, period strip.
class ExpensesListScreen extends ConsumerStatefulWidget {
  const ExpensesListScreen({super.key, required this.labels});

  final ExpensesListScreenLabels labels;

  @override
  ConsumerState<ExpensesListScreen> createState() => _ExpensesListScreenState();
}

class _ExpensesListScreenState extends ConsumerState<ExpensesListScreen> {
  bool _balanceExpanded = false;
  final Set<int> _expandedYears = {};

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(expensesOverviewProvider);
    final locale = Localizations.localeOf(context).toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.labels.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: widget.labels.addExpenseTooltip,
            onPressed: () => openAddExpenseFromShell(
              context: context,
              ref: ref,
              pickerTitle: widget.labels.pickerTitle,
              lastUsedLabel: widget.labels.pickerLastUsed,
            ),
          ),
        ],
      ),
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorState(
          screen: 'expenses',
          message: widget.labels.loadError,
          onRetry: () => ref.invalidate(expensesOverviewProvider),
        ),
        data: (data) {
          if (data.rollups.isEmpty) {
            return AppEmptyState(
              screen: 'expenses',
              icon: Icons.receipt_long_outlined,
              title: widget.labels.emptyTitle,
              subtitle: widget.labels.emptySubtitle,
            );
          }

          final partitioned = partitionRollupsByRecency(data.rollups);
          final years = partitioned.earlierByYear.keys.toList()
            ..sort((a, b) => b.compareTo(a));

          return ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
            children: [
              _BalanceHeaderCard(
                labels: widget.labels,
                summary: data.balanceSummary,
                expanded: _balanceExpanded,
                locale: locale,
                onToggle: () =>
                    setState(() => _balanceExpanded = !_balanceExpanded),
                onTripTap: (tripId) =>
                    context.push(AppRoutes.tripBalances(tripId)),
              ),
              const SizedBox(height: 16),
              _PeriodStrip(
                labels: widget.labels,
                totals: data.periodTotals,
                locale: locale,
              ),
              const SizedBox(height: 20),
              Text(
                widget.labels.balanceAcrossTrips,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              for (final rollup in partitioned.recent)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 8),
                  child: _TripRollupTile(
                    rollup: rollup,
                    labels: widget.labels,
                    locale: locale,
                    onTap: () {
                      ref.read(analyticsProvider).capture(
                            VamoEvent.tripRollupOpened,
                            properties: {'trip_id': rollup.tripId},
                          );
                      context.push(AppRoutes.trip(rollup.tripId));
                    },
                  ),
                ),
              if (years.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final year in years)
                  _YearSection(
                    year: year,
                    rollups: partitioned.earlierByYear[year]!,
                    labels: widget.labels,
                    locale: locale,
                    expanded: _expandedYears.contains(year),
                    onExpansionChanged: (open) {
                      setState(() {
                        if (open) {
                          _expandedYears.add(year);
                        } else {
                          _expandedYears.remove(year);
                        }
                      });
                    },
                    onTripTap: (rollup) {
                      ref.read(analyticsProvider).capture(
                            VamoEvent.tripRollupOpened,
                            properties: {'trip_id': rollup.tripId},
                          );
                      context.push(AppRoutes.trip(rollup.tripId));
                    },
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BalanceHeaderCard extends StatelessWidget {
  const _BalanceHeaderCard({
    required this.labels,
    required this.summary,
    required this.expanded,
    required this.locale,
    required this.onToggle,
    required this.onTripTap,
  });

  final ExpensesListScreenLabels labels;
  final CrossTripBalanceSummary summary;
  final bool expanded;
  final String locale;
  final VoidCallback onToggle;
  final void Function(String tripId) onTripTap;

  @override
  Widget build(BuildContext context) {
    final primaryOwe = _primaryAmount(summary.oweCentsByCurrency);
    final primaryOwed = _primaryAmount(summary.owedCentsByCurrency);

    final headline = summary.allSettled
        ? labels.balanceAllSettled
        : [
            if (primaryOwe != null)
              labels.balanceYouOwe(
                formatMoneyFromCents(
                  primaryOwe.$2,
                  primaryOwe.$1,
                  locale: locale,
                ),
                summary.oweTripCount,
              ),
            if (primaryOwed != null)
              labels.balanceYouAreOwed(
                formatMoneyFromCents(
                  primaryOwed.$2,
                  primaryOwed.$1,
                  locale: locale,
                ),
              ),
          ].join(' · ');

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: summary.perTripRows.isEmpty ? null : onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsetsDirectional.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      headline,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (summary.perTripRows.isNotEmpty)
                    Icon(
                      expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: AppColors.graphite,
                    ),
                ],
              ),
            ),
          ),
          if (expanded)
            for (final row in summary.perTripRows)
              ListTile(
                dense: true,
                title: Text(row.tripName),
                trailing: Text(
                  formatMoneyFromCents(
                    row.netCents.abs(),
                    row.currency,
                    locale: locale,
                  ),
                  style: TextStyle(
                    color: row.netCents < 0
                        ? AppColors.coralText
                        : AppColors.jadeTeal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  row.netCents < 0 ? 'You owe' : "You're owed",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.graphite,
                      ),
                ),
                onTap: () => onTripTap(row.tripId),
              ),
        ],
      ),
    );
  }

  (String, int)? _primaryAmount(Map<String, int> byCurrency) {
    if (byCurrency.isEmpty) return null;
    final entry = byCurrency.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return (entry.key, entry.value);
  }
}

class _PeriodStrip extends StatelessWidget {
  const _PeriodStrip({
    required this.labels,
    required this.totals,
    required this.locale,
  });

  final ExpensesListScreenLabels labels;
  final PeriodTotals totals;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final currency = totals.primaryCurrency;
    final month = currency == null
        ? '—'
        : formatMoneyFromCents(
            totals.monthByCurrency[currency] ?? 0,
            currency,
            locale: locale,
          );
    final year = currency == null
        ? '—'
        : formatMoneyFromCents(
            totals.yearByCurrency[currency] ?? 0,
            currency,
            locale: locale,
          );

    return Row(
      children: [
        Expanded(
          child: _PeriodChip(
            label: labels.periodThisMonth,
            amount: month,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PeriodChip(
            label: labels.periodThisYear,
            amount: year,
          ),
        ),
      ],
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label, required this.amount});

  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.mistGray.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.graphite,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              amount,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripRollupTile extends StatelessWidget {
  const _TripRollupTile({
    required this.rollup,
    required this.labels,
    required this.locale,
    required this.onTap,
  });

  final TripExpenseRollup rollup;
  final ExpensesListScreenLabels labels;
  final String locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badge = switch (rollup.settlementState) {
      TripRollupSettlementState.unsettled => (
          labels.settlementUnsettled,
          AppColors.coralText.withValues(alpha: 0.12),
          AppColors.coralText,
        ),
      TripRollupSettlementState.settled => (
          labels.settlementSettled,
          AppColors.blush,
          AppColors.jadeTeal,
        ),
      TripRollupSettlementState.allSettled => (
          labels.settlementAllSettled,
          AppColors.goLime,
          AppColors.ink,
        ),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rollup.tripName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      badge.$1,
                      style: TextStyle(
                        color: badge.$3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: badge.$2,
                    side: BorderSide.none,
                  ),
                  if (rollup.isUnresolved) ...[
                    const SizedBox(width: 6),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        labels.unresolvedBadge,
                        style: const TextStyle(
                          color: AppColors.coralText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      backgroundColor: AppColors.coralText.withValues(alpha: 0.12),
                      side: BorderSide.none,
                    ),
                  ],
                ],
              ),
              if (rollup.dateRange != null) ...[
                const SizedBox(height: 4),
                Text(
                  rollup.dateRange!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.graphite,
                      ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '${labels.totalSpent} ${formatMoneyFromCentsBidi(rollup.totalSpentCents, rollup.currency, locale: locale)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                '${labels.myShare} ${formatMoneyFromCentsBidi(rollup.myShareCents, rollup.currency, locale: locale)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.graphite,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YearSection extends StatelessWidget {
  const _YearSection({
    required this.year,
    required this.rollups,
    required this.labels,
    required this.locale,
    required this.expanded,
    required this.onExpansionChanged,
    required this.onTripTap,
  });

  final int year;
  final List<TripExpenseRollup> rollups;
  final ExpensesListScreenLabels labels;
  final String locale;
  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;
  final void Function(TripExpenseRollup rollup) onTripTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        onExpansionChanged: onExpansionChanged,
        title: Text(
          '${labels.earlierSection} · $year',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        children: [
          for (final rollup in rollups)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 8),
              child: _TripRollupTile(
                rollup: rollup,
                labels: labels,
                locale: locale,
                onTap: () => onTripTap(rollup),
              ),
            ),
        ],
      ),
    );
  }
}
