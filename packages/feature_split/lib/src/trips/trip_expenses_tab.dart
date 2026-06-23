import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../expenses/expense_consent_providers.dart';
import '../expenses/expense_detail_sheet.dart';
import '../expenses/expense_governance.dart';
import '../expenses/expense_governance_labels.dart';
import '../expenses/expenses_providers.dart';
import '../expenses/trip_expense_list_tile.dart';
import '../expenses/trip_expenses_balances_link.dart';
import '../expenses/trip_expenses_propose_action.dart';
import 'trip_budget_labels.dart';

/// Expense list body shared by trip expenses section.
class TripExpensesTab extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(tripExpensesProvider(tripId));
    final members = ref.watch(tripMembersForExpenseProvider(tripId));
    final consentFlags = ref.watch(tripShareConsentFlagsProvider(tripId));
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final role = ref.watch(
      currentMemberRoleProvider((tripId: tripId, userId: currentUserId)),
    );
    final canManageProposals =
        !readOnly && role != null && canEditTripProposals(role);

    // Group trips only: solo trips have no balances. Hidden while members are
    // still loading (valueOrNull == null) so the link never flickers in.
    final memberCount = members.valueOrNull?.length ?? 0;
    final showBalancesLink = memberCount > 1;

    return expenses.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorState(
        screen: 'trip_expenses',
        message: 'Could not load expenses.',
        onRetry: () => ref.invalidate(tripExpensesProvider(tripId)),
      ),
      data: (list) {
        final nameByUserId = members.valueOrNull == null
            ? <String, String>{}
            : {
                for (final m in members.requireValue) m.userId: m.displayName,
              };

        final consentByExpense = {
          for (final flag in consentFlags)
            flag.expenseId: governanceLabels.consentDisplayLabel(
              memberName:
                  nameByUserId[flag.userId] ??
                  fallbackMemberDisplayName(userId: flag.userId),
              response: flag.response,
            ),
        };

        if (list.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TripExpensesBalancesLink(
                tripId: tripId,
                label: balancesLabel,
                visible: showBalancesLink,
              ),
              TripExpensesProposeAction(
                visible: canManageProposals,
                labels: governanceLabels,
                onPressed: () =>
                    context.push(AppRoutes.tripProposeExpense(tripId)),
              ),
              const Expanded(
                child: AppEmptyState(
                  screen: 'trip_expenses',
                  icon: Icons.receipt_long_outlined,
                  title: 'No expenses yet',
                  subtitle: 'Tap Add expense to log your first cost.',
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TripExpensesBalancesLink(
              tripId: tripId,
              label: balancesLabel,
              visible: showBalancesLink,
            ),
            TripExpensesProposeAction(
              visible: canManageProposals,
              labels: governanceLabels,
              onPressed: () =>
                  context.push(AppRoutes.tripProposeExpense(tripId)),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final e = list[i];
                  if (e.status == ExpenseStatus.cancelled) {
                    return const SizedBox.shrink();
                  }
                  final payer = nameByUserId[e.payerId] ??
                      fallbackMemberDisplayName(userId: e.payerId);
                  final locale = Localizations.localeOf(context).toString();
                  return TripExpenseListTile(
                    description: e.description,
                    payer: payer,
                    spentAt: e.spentAt,
                    baseCents: e.baseCents,
                    amountCents: e.amountCents,
                    tripBaseCurrency: baseCurrency,
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
                    proposalRowPrefix: governanceLabels.proposalRowPrefix,
                    onTap: () => showExpenseDetailSheet(
                      context: context,
                      ref: ref,
                      expense: e,
                      tripBaseCurrency: baseCurrency,
                      labels: governanceLabels,
                      budgetLabels: budgetLabels,
                      readOnly: readOnly,
                      canManageProposals: canManageProposals,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
