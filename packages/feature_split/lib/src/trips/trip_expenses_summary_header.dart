import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../expenses/expense_governance_labels.dart';
import '../expenses/money_format.dart';
import '../expenses/trip_expenses_balances_link.dart';
import '../expenses/trip_spend_summary.dart';

/// Spend-led summary header (§B): **Total spent** + **Your share** for the
/// trip, with a quiet `Balances ›` link (group trips only) connecting the two
/// money surfaces. The net-balance donut stays on Balances — this surfaces
/// spend, not net position ("connected, not duplicated").
class TripExpensesSummaryHeader extends ConsumerWidget {
  const TripExpensesSummaryHeader({
    super.key,
    required this.tripId,
    required this.baseCurrency,
    required this.labels,
    required this.balancesLabel,
    required this.showBalancesLink,
    this.locale,
  });

  final String tripId;
  final String baseCurrency;
  final ExpenseGovernanceLabels labels;
  final String balancesLabel;
  final bool showBalancesLink;
  final String? locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(tripSpendSummaryProvider(tripId));
    final total = formatMoneyFromCents(
      summary.totalSpentCents,
      baseCurrency,
      locale: locale,
    );
    final share = formatMoneyFromCents(
      summary.yourShareCents,
      baseCurrency,
      locale: locale,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 14),
        child: Row(
          children: [
            Expanded(
              child: _Metric(
                label: labels.totalSpent,
                value: total,
                emphatic: true,
              ),
            ),
            Expanded(
              child: _Metric(label: labels.yourShare, value: share),
            ),
            TripExpensesBalancesLink(
              tripId: tripId,
              label: balancesLabel,
              visible: showBalancesLink,
              foregroundColor: AppColors.sunsetCoral,
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.emphatic = false,
  });

  final String label;
  final String value;
  final bool emphatic;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelSmall?.copyWith(
            color: AppColors.mistGray,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (emphatic ? textTheme.titleLarge : textTheme.titleMedium)
              ?.copyWith(
                color: AppColors.surface,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
