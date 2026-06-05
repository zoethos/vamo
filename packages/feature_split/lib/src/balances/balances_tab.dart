import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../expenses/expense_consent_providers.dart';
import '../expenses/expenses_providers.dart';
import '../expenses/money_format.dart';
import '../settle/settlements_providers.dart';
import '../settle/settlements_repository.dart';
import 'balances_providers.dart';
import 'mark_settle_sheet.dart';

/// Slice 4 — settle-up, mark/confirm/revoke, honest payment handoff labels.
class BalancesTab extends ConsumerWidget {
  const BalancesTab({super.key, required this.tripId});

  final String tripId;

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

    return settlements.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorState(
        screen: 'trip_balances',
        message: 'Could not load balances.',
        onRetry: () => ref.invalidate(tripSettleUpProvider(tripId)),
      ),
      data: (lines) {
        final nameById = members.valueOrNull == null
            ? <String, String>{}
            : {for (final m in members.requireValue) m.userId: m.displayName};
        final consentFlags = ref.watch(tripShareConsentFlagsProvider(tripId));
        final consentLabels =
            consentFlags.map((f) => f.label).toSet().toList(growable: false);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (pending.isNotEmpty) ...[
              _sectionTitle(context, 'Confirm payments'),
              Text(
                'Marked as paid — confirm if you received it, or reject if not.',
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
                          '${nameById[s.fromUserId] ?? 'Someone'} says they paid you',
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
                                child: const Text('Confirm'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _revoke(
                                  context,
                                  ref,
                                  s.id,
                                  successMessage: 'Marked as not received.',
                                ),
                                child: const Text('Reject'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (payerAwaiting.isNotEmpty) ...[
              _sectionTitle(context, 'Awaiting confirmation'),
              Text(
                'You marked these paid — recipients can confirm or reject. Cancel if you did not actually pay.',
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
                      'You → ${nameById[s.toUserId] ?? 'Someone'}',
                    ),
                    subtitle: Text(
                      '${formatMoneyFromCents(s.amountCents, s.currency)} · marked, not confirmed',
                    ),
                    trailing: TextButton(
                      onPressed: () => _revoke(
                        context,
                        ref,
                        s.id,
                        successMessage: 'Mark cancelled — debt is back on your balance.',
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (lines.isEmpty && pending.isEmpty && payerAwaiting.isEmpty)
              const AppEmptyState(
                screen: 'trip_balances',
                icon: Icons.check_circle_outline,
                title: 'All square',
                subtitle: 'No open debts — add expenses or invite Vamigos.',
              )
            else if (lines.isNotEmpty) ...[
              _sectionTitle(context, 'Settle up'),
              Text(
                'Fewest payments to clear the trip.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.graphite),
              ),
              const SizedBox(height: 16),
              ...lines.map(
                (s) {
                  final isPayer = currentUserId == s.line.fromUserId;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppColors.blush,
                                child: Icon(
                                  Directionality.of(context) ==
                                          TextDirection.rtl
                                      ? Icons.arrow_back
                                      : Icons.arrow_forward,
                                  color: AppColors.ink,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${s.fromName} pays ${s.toName}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    Text(
                                      formatMoneyFromCents(
                                        s.line.cents,
                                        s.currency,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            color: AppColors.jadeTeal,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
                                child: const Text('Mark as settled'),
                              ),
                            ),
                          ] else
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Waiting for ${s.fromName} to pay',
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
            ],
            _NetBalancesSection(
              tripId: tripId,
              nameById: nameById,
              currency: currency,
              consentFlags: ref.watch(tripShareConsentFlagsProvider(tripId)),
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
          const SnackBar(content: Text('Payment confirmed.')),
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

class _NetBalancesSection extends ConsumerWidget {
  const _NetBalancesSection({
    required this.tripId,
    required this.nameById,
    required this.currency,
    required this.consentFlags,
  });

  final String tripId;
  final Map<String, String> nameById;
  final String currency;
  final List<({String userId, String label, String expenseId})> consentFlags;

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
        const SizedBox(height: 24),
        Text(
          'Net balances',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.graphite,
              ),
        ),
        const SizedBox(height: 8),
        for (final e in nonZero)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${nameById[e.key] ?? 'Someone'} '
              '${e.value > 0 ? 'is owed' : 'owes'} '
              '${formatMoneyFromCents(e.value.abs(), currency)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        for (final flag in consentFlags)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              flag.label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.graphite,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
      ],
    );
  }
}
