import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../expenses/expense_consent_providers.dart';
import '../expenses/expense_detail_sheet.dart';
import '../expenses/expense_governance.dart';
import '../expenses/expense_governance_labels.dart';
import '../expenses/expense_models.dart';
import '../expenses/expenses_providers.dart';
import '../expenses/money_format.dart';
import '../expenses/trip_expense_list_tile.dart';
import '../expenses/trip_expenses_propose_action.dart';
import 'trip_budget_labels.dart';
import 'trip_expenses_summary_header.dart';

/// Day-grouped list filter (§C). Resets per visit.
enum ExpenseListFilter { all, unsettled, mine }

/// Expense list body shared by the trip expenses section — spend-led summary
/// header, day-grouped M3 rows with subtotals, filter chips, and the reserved
/// lime action FAB.
class TripExpensesTab extends ConsumerStatefulWidget {
  const TripExpensesTab({
    super.key,
    required this.tripId,
    required this.baseCurrency,
    required this.readOnly,
    required this.governanceLabels,
    required this.budgetLabels,
    required this.balancesLabel,
  });

  final String tripId;
  final String baseCurrency;
  final bool readOnly;
  final ExpenseGovernanceLabels governanceLabels;
  final TripBudgetLabels budgetLabels;
  final String balancesLabel;

  @override
  ConsumerState<TripExpensesTab> createState() => _TripExpensesTabState();
}

class _TripExpensesTabState extends ConsumerState<TripExpensesTab> {
  ExpenseListFilter _filter = ExpenseListFilter.all;

  String get _tripId => widget.tripId;

  @override
  Widget build(BuildContext context) {
    final expenses = ref.watch(tripExpensesProvider(_tripId));
    final members = ref.watch(tripMembersForExpenseProvider(_tripId));
    final shares = ref.watch(tripExpenseSharesProvider(_tripId)).valueOrNull ??
        const <ExpenseShareSummary>[];
    final consentFlags = ref.watch(tripShareConsentFlagsProvider(_tripId));
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final role = ref.watch(
      currentMemberRoleProvider((tripId: _tripId, userId: currentUserId)),
    );
    final canManageProposals =
        !widget.readOnly && role != null && canEditTripProposals(role);

    // Group trips only: solo trips have no balances. Hidden while members are
    // still loading (valueOrNull == null) so the link never flickers in.
    final memberCount = members.valueOrNull?.length ?? 0;
    final showBalancesLink = memberCount > 1;

    final fab = TripExpensesProposeAction(
      visible: canManageProposals,
      labels: widget.governanceLabels,
      mode: AddExpenseMode.proposed,
      onPressed: () => context.push(AppRoutes.tripProposeExpense(_tripId)),
    );

    final body = expenses.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorState(
        screen: 'trip_expenses',
        message: 'Could not load expenses.',
        onRetry: () => ref.invalidate(tripExpensesProvider(_tripId)),
      ),
      data: (list) => _buildLoaded(
        context: context,
        list: list,
        members: members,
        shares: shares,
        consentFlags: consentFlags,
        currentUserId: currentUserId,
        canManageProposals: canManageProposals,
        showBalancesLink: showBalancesLink,
      ),
    );

    return Stack(
      children: [
        Positioned.fill(child: body),
        PositionedDirectional(
          end: 16,
          bottom: 16,
          child: fab,
        ),
      ],
    );
  }

  Widget _buildLoaded({
    required BuildContext context,
    required List<ExpenseSummary> list,
    required AsyncValue<List<TripMemberView>> members,
    required List<ExpenseShareSummary> shares,
    required List<({String userId, ShareResponse response, String expenseId})>
        consentFlags,
    required String? currentUserId,
    required bool canManageProposals,
    required bool showBalancesLink,
  }) {
    final nameByUserId = members.valueOrNull == null
        ? <String, String>{}
        : {
            for (final m in members.requireValue) m.userId: m.displayName,
          };

    final consentByExpense = {
      for (final flag in consentFlags)
        flag.expenseId: widget.governanceLabels.consentDisplayLabel(
          memberName: nameByUserId[flag.userId] ??
              fallbackMemberDisplayName(userId: flag.userId),
          response: flag.response,
        ),
    };

    // Filter inputs: expenses the current user shares, and committed expenses
    // with an unresolved consent flag (the "Unsettled" proxy).
    final myShareExpenseIds = <String>{
      for (final s in shares)
        if (currentUserId != null && s.userId == currentUserId) s.expenseId,
    };
    final unsettledExpenseIds = {for (final f in consentFlags) f.expenseId};

    final visible = [
      for (final e in list)
        if (e.status != ExpenseStatus.cancelled &&
            _matchesFilter(
              e,
              currentUserId: currentUserId,
              myShareExpenseIds: myShareExpenseIds,
              unsettledExpenseIds: unsettledExpenseIds,
            ))
          e,
    ];

    final locale = Localizations.localeOf(context).toString();
    final labels = widget.governanceLabels;

    final header = TripExpensesSummaryHeader(
      tripId: _tripId,
      baseCurrency: widget.baseCurrency,
      labels: labels,
      balancesLabel: widget.balancesLabel,
      showBalancesLink: showBalancesLink,
      locale: locale,
    );

    final filters = _FilterChips(
      selected: _filter,
      labels: labels,
      onSelected: (f) => setState(() => _filter = f),
    );

    Widget listArea;
    if (visible.isEmpty) {
      final noneAtAll = list.every((e) => e.status == ExpenseStatus.cancelled) ||
          list.isEmpty;
      listArea = Expanded(
        child: AppEmptyState(
          screen: 'trip_expenses',
          icon: Icons.receipt_long_outlined,
          title: noneAtAll ? 'No expenses yet' : 'Nothing matches',
          subtitle: noneAtAll
              ? 'Tap + to log your first expense.'
              : 'No expenses match this filter.',
        ),
      );
    } else {
      final rows = _buildRows(visible);
      listArea = Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final row = rows[i];
            if (row is _DayHeaderRow) {
              return _DayHeader(
                title: _dayLabel(row.day, labels.todayLabel),
                subtotal: formatMoneyFromCents(
                  row.subtotalCents,
                  widget.baseCurrency,
                  locale: locale,
                ),
              );
            }
            final e = (row as _ExpenseRow).expense;
            final payer = nameByUserId[e.payerId] ??
                fallbackMemberDisplayName(userId: e.payerId);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TripExpenseListTile(
                description: e.description,
                payer: payer,
                spentAt: e.spentAt,
                baseCents: e.baseCents,
                amountCents: e.amountCents,
                tripBaseCurrency: widget.baseCurrency,
                expenseCurrency: e.currency,
                locale: locale,
                expenseId: e.id,
                tripId: e.tripId,
                receiptPath: e.receiptPath,
                localReceiptPath: e.localReceiptPath,
                placeLabel: e.placeLabel,
                category: e.category,
                status: e.status,
                consentLabel: consentByExpense[e.id],
                proposalRowPrefix: labels.proposalRowPrefix,
                onTap: () => showExpenseDetailSheet(
                  context: context,
                  ref: ref,
                  expense: e,
                  tripBaseCurrency: widget.baseCurrency,
                  labels: labels,
                  budgetLabels: widget.budgetLabels,
                  readOnly: widget.readOnly,
                  canManageProposals: canManageProposals,
                ),
              ),
            );
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, filters, listArea],
    );
  }

  bool _matchesFilter(
    ExpenseSummary e, {
    required String? currentUserId,
    required Set<String> myShareExpenseIds,
    required Set<String> unsettledExpenseIds,
  }) {
    switch (_filter) {
      case ExpenseListFilter.all:
        return true;
      case ExpenseListFilter.mine:
        return e.payerId == currentUserId || myShareExpenseIds.contains(e.id);
      case ExpenseListFilter.unsettled:
        return unsettledExpenseIds.contains(e.id);
    }
  }

  /// Flattens day-sorted expenses into header + expense rows with day subtotals.
  List<_Row> _buildRows(List<ExpenseSummary> expenses) {
    final sorted = [...expenses]
      ..sort((a, b) => b.spentAt.compareTo(a.spentAt));
    final rows = <_Row>[];
    DateTime? currentDay;
    var headerIndex = -1;
    var subtotal = 0;
    for (final e in sorted) {
      final day = DateTime(e.spentAt.year, e.spentAt.month, e.spentAt.day);
      if (currentDay == null || day != currentDay) {
        if (headerIndex >= 0) {
          (rows[headerIndex] as _DayHeaderRow).subtotalCents = subtotal;
        }
        currentDay = day;
        subtotal = 0;
        rows.add(_DayHeaderRow(day));
        headerIndex = rows.length - 1;
      }
      subtotal += e.baseCents;
      rows.add(_ExpenseRow(e));
    }
    if (headerIndex >= 0) {
      (rows[headerIndex] as _DayHeaderRow).subtotalCents = subtotal;
    }
    return rows;
  }

  String _dayLabel(DateTime day, String todayLabel) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final formatted = DateFormat('MMM d').format(day).toUpperCase();
    if (day == today) return '${todayLabel.toUpperCase()} · $formatted';
    return formatted;
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.selected,
    required this.labels,
    required this.onSelected,
  });

  final ExpenseListFilter selected;
  final ExpenseGovernanceLabels labels;
  final ValueChanged<ExpenseListFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = <(ExpenseListFilter, String)>[
      (ExpenseListFilter.all, labels.filterAll),
      (ExpenseListFilter.unsettled, labels.filterUnsettled),
      (ExpenseListFilter.mine, labels.filterMine),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          for (final (value, label) in options)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: selected == value,
                onSelected: (_) => onSelected(value),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.title, required this.subtotal});

  final String title;
  final String subtotal;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.labelMedium?.copyWith(
      color: AppColors.neutralMid,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        children: [
          Expanded(child: Text(title, style: style)),
          Text(subtotal, style: style),
        ],
      ),
    );
  }
}

sealed class _Row {
  const _Row();
}

class _DayHeaderRow extends _Row {
  _DayHeaderRow(this.day);
  final DateTime day;
  int subtotalCents = 0;
}

class _ExpenseRow extends _Row {
  const _ExpenseRow(this.expense);
  final ExpenseSummary expense;
}
