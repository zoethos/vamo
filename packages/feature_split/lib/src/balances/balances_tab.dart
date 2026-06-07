import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../expenses/expense_consent_providers.dart';
import '../expenses/expense_governance_labels.dart';
import '../expenses/expenses_providers.dart';
import '../expenses/money_format.dart';
import '../settle/settlements_providers.dart';
import '../settle/settlements_repository.dart';
import 'balances_providers.dart';
import 'balances_tab_labels.dart';
import 'mark_settle_sheet.dart';

/// Slice 4 — settle-up with S27 scan-first hierarchy.
class BalancesTab extends ConsumerWidget {
  const BalancesTab({
    super.key,
    required this.tripId,
    required this.governanceLabels,
    required this.labels,
  });

  final String tripId;
  final ExpenseGovernanceLabels governanceLabels;
  final BalancesTabLabels labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settlements = ref.watch(tripSettleUpProvider(tripId));
    final pending = ref.watch(tripPendingConfirmationsProvider(tripId));
    final payerAwaiting = ref.watch(tripPayerAwaitingConfirmProvider(tripId));
    final members = ref.watch(tripMembersForExpenseProvider(tripId));
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final currency =
        ref.watch(tripNetBalancesProvider(tripId)).valueOrNull?.currency ??
            'EUR';
    final consentFlags = ref.watch(tripShareConsentFlagsProvider(tripId));

    return settlements.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorState(
        screen: 'trip_balances',
        message: labels.loadError,
        onRetry: () => ref.invalidate(tripSettleUpProvider(tripId)),
      ),
      data: (lines) {
        final nameById = members.valueOrNull == null
            ? <String, String>{}
            : {for (final m in members.requireValue) m.userId: m.displayName};
        final someone = labels.someoneFallback;
        final consentLabels = consentFlags
            .map(
              (f) => governanceLabels.consentDisplayLabel(
                memberName: nameById[f.userId] ?? someone,
                response: f.response,
              ),
            )
            .where((label) => label.isNotEmpty)
            .toSet()
            .toList(growable: false);

        final hasMyAction = pending.isNotEmpty || payerAwaiting.isNotEmpty;
        final isEmpty =
            lines.isEmpty && !hasMyAction && consentLabels.isEmpty;

        if (isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppEmptyState(
                screen: 'trip_balances',
                icon: Icons.check_circle_outline,
                title: labels.emptyTitle,
                subtitle: labels.emptySubtitle,
              ),
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (lines.isNotEmpty) ...[
              _sectionTitle(context, labels.whoOwesWhomTitle),
              Text(
                labels.whoOwesWhomHint,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.graphite),
              ),
              const SizedBox(height: 12),
              ...lines.map(
                (s) {
                  final isPayer = currentUserId == s.line.fromUserId;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            labels.paysLine(s.fromName, s.toName),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            formatMoneyFromCents(s.line.cents, s.currency),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: AppColors.jadeTeal,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if (isPayer) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () => showMarkSettleSheet(
                                  context: context,
                                  ref: ref,
                                  tripId: tripId,
                                  display: s,
                                  consentLabels: consentLabels,
                                ),
                                child: Text(labels.markAsSettled),
                              ),
                            ),
                          ] else
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                labels.waitingForPayer(s.fromName),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.graphite),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
            if (consentLabels.isNotEmpty) ...[
              _sectionTitle(context, labels.disputedTitle),
              ...consentLabels.map(
                (label) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.coralText,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (hasMyAction) ...[
              _sectionTitle(context, labels.myActionTitle),
              if (pending.isNotEmpty) ...[
                Text(
                  labels.confirmPaymentsHint,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.graphite),
                ),
                const SizedBox(height: 12),
                ...pending.map(
                  (s) => Card(
                    color: AppColors.blush,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            labels.confirmPaymentFrom(
                              nameById[s.fromUserId] ?? someone,
                            ),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            formatMoneyFromCents(s.amountCents, s.currency),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: AppColors.jadeTeal,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: () =>
                                      _confirm(context, ref, s.id),
                                  child: Text(labels.confirm),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _revoke(
                                    context,
                                    ref,
                                    s.id,
                                    successMessage: labels.markedNotReceived,
                                  ),
                                  child: Text(labels.reject),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (payerAwaiting.isNotEmpty) ...[
                if (pending.isNotEmpty) const SizedBox(height: 16),
                Text(
                  labels.awaitingConfirmationHint,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.graphite),
                ),
                const SizedBox(height: 12),
                ...payerAwaiting.map(
                  (s) => Card(
                    child: ListTile(
                      title: Text(
                        labels.youToRecipient(
                          nameById[s.toUserId] ?? someone,
                        ),
                      ),
                      subtitle: Text(
                        labels.markedNotConfirmed(
                          formatMoneyFromCents(s.amountCents, s.currency),
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: () => _revoke(
                          context,
                          ref,
                          s.id,
                          successMessage: labels.markCancelled,
                        ),
                        child: Text(labels.cancelMark),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
            _FinalBalancesSection(
              tripId: tripId,
              nameById: nameById,
              currency: currency,
              labels: labels,
            ),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    String settlementId,
  ) async {
    try {
      await ref
          .read(settlementsRepositoryProvider)
          .confirmSettlement(settlementId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(labels.paymentConfirmed)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showActionError(
          context,
          ref,
          screen: 'trip_home',
          action: 'confirm_settlement',
          error: e,
        );
      }
    }
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    String settlementId, {
    required String successMessage,
  }) async {
    try {
      await ref
          .read(settlementsRepositoryProvider)
          .revokeMarkedSettlement(settlementId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showActionError(
          context,
          ref,
          screen: 'trip_home',
          action: 'revoke_settlement',
          error: e,
        );
      }
    }
  }
}

class _FinalBalancesSection extends ConsumerWidget {
  const _FinalBalancesSection({
    required this.tripId,
    required this.nameById,
    required this.currency,
    required this.labels,
  });

  final String tripId;
  final Map<String, String> nameById;
  final String currency;
  final BalancesTabLabels labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawNets =
        ref.watch(tripNetBalancesProvider(tripId)).valueOrNull?.nets;
    if (rawNets == null) return const SizedBox.shrink();
    final nonZero = rawNets.entries.where((e) => e.value != 0).toList();
    if (nonZero.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labels.finalTitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        for (final e in nonZero)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              labels.netBalanceLine(
                nameById[e.key] ?? labels.someoneFallback,
                e.value > 0,
                formatMoneyFromCents(e.value.abs(), currency),
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}
