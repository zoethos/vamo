import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'expense_consent_providers.dart';
import 'expense_governance.dart';
import 'expense_models.dart';
import 'expenses_providers.dart';
import 'expenses_repository.dart';
import 'money_format.dart';

Future<void> showExpenseDetailSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ExpenseSummary expense,
  required bool readOnly,
  required bool canManageProposals,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ExpenseDetailSheet(
      expense: expense,
      readOnly: readOnly,
      canManageProposals: canManageProposals,
    ),
  );
}

class _ExpenseDetailSheet extends ConsumerWidget {
  const _ExpenseDetailSheet({
    required this.expense,
    required this.readOnly,
    required this.canManageProposals,
  });

  final ExpenseSummary expense;
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
                'Proposal — not in balances until committed',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.graphite,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            const SizedBox(height: 16),
            for (final share in shares.where((s) => s.expenseId == expense.id))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(names[share.userId] ?? 'Someone'),
                subtitle: Text(
                  shareConsentDisplayLabel(
                        memberName: names[share.userId] ?? 'Someone',
                        response: share.response,
                      ).isEmpty
                      ? 'Accepted'
                      : shareConsentDisplayLabel(
                          memberName: names[share.userId] ?? 'Someone',
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
                'Your share',
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
                      child: const Text('Dispute'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: myShare.response == ShareResponse.accepted
                          ? null
                          : () => _respond(context, ref, repo, accept: true),
                      child: const Text('Accept'),
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
                child: const Text('Commit to balances'),
              ),
              TextButton(
                onPressed: () async {
                  await repo.voidExpense(expense.id);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Void proposal'),
              ),
            ],
          ],
        ),
      ),
    );
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
        title: const Text('Why are you disputing?'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Reason'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Submit'),
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