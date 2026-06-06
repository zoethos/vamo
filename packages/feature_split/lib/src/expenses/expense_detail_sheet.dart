import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'expense_consent_providers.dart';
import 'expense_governance.dart';
import 'expense_governance_labels.dart';
import 'expense_models.dart';
import 'expenses_providers.dart';
import 'expenses_repository.dart';
import 'money_format.dart';

Future<void> showExpenseDetailSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ExpenseSummary expense,
  required ExpenseGovernanceLabels labels,
  required bool readOnly,
  required bool canManageProposals,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ExpenseDetailSheet(
      expense: expense,
      labels: labels,
      readOnly: readOnly,
      canManageProposals: canManageProposals,
    ),
  );
}

class _ExpenseDetailSheet extends ConsumerWidget {
  const _ExpenseDetailSheet({
    required this.expense,
    required this.labels,
    required this.readOnly,
    required this.canManageProposals,
  });

  final ExpenseSummary expense;
  final ExpenseGovernanceLabels labels;
  final bool readOnly;
  final bool canManageProposals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shares =
        ref.watch(tripExpenseSharesProvider(expense.tripId)).valueOrNull ?? [];
    final members =
        ref.watch(tripMembersForExpenseProvider(expense.tripId)).valueOrNull ??
            [];
    final names = {for (final m in members) m.userId: m.displayName};
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final myShare = shares
        .where((s) => s.expenseId == expense.id && s.userId == currentUserId)
        .firstOrNull;
    final repo = ref.read(expensesRepositoryProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              expense.description,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (expense.status == ExpenseStatus.proposed)
              Text(
                labels.proposalNotInBalances,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.graphite,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            const SizedBox(height: 16),
            for (final share in shares.where((s) => s.expenseId == expense.id))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  names[share.userId] ?? labels.someoneFallback,
                ),
                subtitle: Text(
                  _shareSubtitle(
                    labels: labels,
                    memberName:
                        names[share.userId] ?? labels.someoneFallback,
                    response: share.response,
                  ),
                ),
                trailing: Text(
                  formatMoneyFromCents(share.shareCents, expense.currency),
                ),
              ),
            if (myShare != null &&
                expense.status.affectsBalances &&
                myShare.userId == currentUserId) ...[
              const Divider(),
              Text(
                labels.yourShare,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _respond(
                        context,
                        ref,
                        repo,
                        accept: false,
                      ),
                      child: Text(labels.dispute),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: myShare.response == ShareResponse.accepted
                          ? null
                          : () => _respond(context, ref, repo, accept: true),
                      child: Text(labels.accept),
                    ),
                  ),
                ],
              ),
            ],
            if (expense.status == ExpenseStatus.proposed &&
                canManageProposals &&
                !readOnly) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  await repo.commitExpense(expense.id);
                  if (context.mounted) Navigator.pop(context);
                },
                child: Text(labels.commitToBalances),
              ),
              TextButton(
                onPressed: () async {
                  await repo.voidExpense(expense.id);
                  if (context.mounted) Navigator.pop(context);
                },
                child: Text(labels.voidProposal),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _shareSubtitle({
    required ExpenseGovernanceLabels labels,
    required String memberName,
    required ShareResponse response,
  }) {
    final flag = labels.consentDisplayLabel(
      memberName: memberName,
      response: response,
    );
    return flag.isEmpty ? labels.shareAccepted : flag;
  }

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref,
    ExpensesRepository repo, {
    required bool accept,
  }) async {
    String? reason;
    if (!accept) {
      reason = await _askReason(context);
      if (reason == null || reason.trim().isEmpty) return;
    }
    try {
      await repo.respondToShare(
        expenseId: expense.id,
        accept: accept,
        reason: reason,
      );
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        showActionError(
          context,
          ref,
          screen: 'expense_detail',
          action: 'respond_to_share',
          error: e,
        );
      }
    }
  }

  Future<String?> _askReason(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels.disputeReasonTitle),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: labels.disputeReasonHint),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(labels.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(labels.submit),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
