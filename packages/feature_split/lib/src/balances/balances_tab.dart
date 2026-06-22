import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../expenses/expense_consent_providers.dart';
import '../expenses/expense_governance_labels.dart';
import '../expenses/expense_models.dart';
import '../expenses/expenses_providers.dart';
import '../expenses/money_format.dart';
import '../settle/settlements_providers.dart';
import '../settle/settlements_repository.dart';
import '../trips/cached_member_avatar.dart';
import 'balances_models.dart';
import 'balances_providers.dart';
import 'balances_tab_labels.dart';
import 'mark_settle_sheet.dart';

const _ink = AppColors.ink;
const _graphite = AppColors.graphite;
const _jade = AppColors.jadeTeal;
const _coral = AppColors.coralText;
const _neutral = AppColors.neutralMid;
const _mist = AppColors.mistGray;

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
        final memberById = members.valueOrNull == null
            ? <String, TripMemberView>{}
            : {for (final m in members.requireValue) m.userId: m};
        final consentLabels = consentFlags
            .map(
              (f) => governanceLabels.consentDisplayLabel(
                memberName: nameById[f.userId] ??
                    fallbackMemberDisplayName(userId: f.userId),
                response: f.response,
              ),
            )
            .where((label) => label.isNotEmpty)
            .toSet()
            .toList(growable: false);

        final hasMyAction = pending.isNotEmpty || payerAwaiting.isNotEmpty;
        final isEmpty = lines.isEmpty && !hasMyAction && consentLabels.isEmpty;
        final rawNets =
            ref.watch(tripNetBalancesProvider(tripId)).valueOrNull?.nets ??
                const <String, int>{};
        final myNet = currentUserId == null ? 0 : rawNets[currentUserId] ?? 0;
        final myPayableLines = currentUserId == null
            ? const <SettlementDisplay>[]
            : lines
                .where((line) => line.line.fromUserId == currentUserId)
                .toList(growable: false);

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
            _NetBalanceHero(
              labels: labels,
              amount: formatMoneyFromCents(myNet.abs(), currency),
              netCents: myNet,
              currency: currency,
              owedTotal: rawNets.values
                  .where((value) => value > 0)
                  .fold<int>(0, (sum, value) => sum + value),
              owedByMe: rawNets.values
                  .where((value) => value < 0)
                  .fold<int>(0, (sum, value) => sum + value.abs()),
              canSettle: myPayableLines.isNotEmpty,
              onSettle: () => _openSettleUp(
                context: context,
                ref: ref,
                lines: myPayableLines,
                consentLabels: consentLabels,
              ),
            ),
            const SizedBox(height: 18),
            if (lines.isNotEmpty) ...[
              _sectionTitle(context, labels.settleUp),
              const SizedBox(height: 12),
              ...lines.map(
                (s) {
                  final isPayer = currentUserId == s.line.fromUserId;
                  return _SettlementRow(
                    display: s,
                    labels: labels,
                    memberById: memberById,
                    isPayer: isPayer,
                    onTap: isPayer
                        ? () => showMarkSettleSheet(
                              context: context,
                              ref: ref,
                              tripId: tripId,
                              display: s,
                              consentLabels: consentLabels,
                            )
                        : null,
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
                          color: _coral,
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
                      ?.copyWith(color: _graphite),
                ),
                const SizedBox(height: 12),
                ...pending.map(
                  (s) => _SettlementStatusRow(
                    leadingMember: memberById[s.fromUserId],
                    fallbackName: nameById[s.fromUserId] ??
                        fallbackMemberDisplayName(userId: s.fromUserId),
                    title: labels.confirmPaymentFrom(
                      nameById[s.fromUserId] ??
                          fallbackMemberDisplayName(userId: s.fromUserId),
                    ),
                    subtitle: '',
                    amount: formatMoneyFromCents(s.amountCents, s.currency),
                    amountColor: _jade,
                    status: labels.statusAwaiting,
                    statusColor: _graphite,
                    actions: [
                      TextButton(
                        onPressed: () => _confirm(context, ref, s.id),
                        child: Text(labels.confirm),
                      ),
                      TextButton(
                        onPressed: () => _revoke(
                          context,
                          ref,
                          s.id,
                          successMessage: labels.markedNotReceived,
                        ),
                        child: Text(labels.reject),
                      ),
                    ],
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
                      ?.copyWith(color: _graphite),
                ),
                const SizedBox(height: 12),
                ...payerAwaiting.map(
                  (s) => _SettlementStatusRow(
                    leadingMember: memberById[s.toUserId],
                    fallbackName: nameById[s.toUserId] ??
                        fallbackMemberDisplayName(userId: s.toUserId),
                    title: labels.youToRecipient(
                      nameById[s.toUserId] ??
                          fallbackMemberDisplayName(userId: s.toUserId),
                    ),
                    subtitle: labels.markedNotConfirmed(
                      formatMoneyFromCents(s.amountCents, s.currency),
                    ),
                    amount: formatMoneyFromCents(s.amountCents, s.currency),
                    amountColor: _coral,
                    status: labels.statusMarkedPaid,
                    statusColor: _graphite,
                    actions: [
                      TextButton(
                        onPressed: () => _revoke(
                          context,
                          ref,
                          s.id,
                          successMessage: labels.markCancelled,
                        ),
                        child: Text(labels.cancelMark),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
            _FinalBalancesSection(
              tripId: tripId,
              nameById: nameById,
              memberById: memberById,
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
            color: _ink,
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Future<void> _openSettleUp({
    required BuildContext context,
    required WidgetRef ref,
    required List<SettlementDisplay> lines,
    required List<String> consentLabels,
  }) async {
    if (lines.isEmpty) return;
    if (lines.length == 1) {
      showMarkSettleSheet(
        context: context,
        ref: ref,
        tripId: tripId,
        display: lines.first,
        consentLabels: consentLabels,
      );
      return;
    }

    final selected = await showModalBottomSheet<SettlementDisplay>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 8),
              child: Text(
                labels.settleUp,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            for (final line in lines)
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text(labels.paysLine(line.fromName, line.toName)),
                trailing: Text(
                  formatMoneyFromCents(line.line.cents, line.currency),
                  style: const TextStyle(
                    color: _coral,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, line),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected == null || !context.mounted) return;
    showMarkSettleSheet(
      context: context,
      ref: ref,
      tripId: tripId,
      display: selected,
      consentLabels: consentLabels,
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

class _NetBalanceHero extends StatelessWidget {
  const _NetBalanceHero({
    required this.labels,
    required this.amount,
    required this.netCents,
    required this.currency,
    required this.owedTotal,
    required this.owedByMe,
    required this.canSettle,
    required this.onSettle,
  });

  final BalancesTabLabels labels;
  final String amount;
  final int netCents;
  final String currency;
  final int owedTotal;
  final int owedByMe;
  final bool canSettle;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = netCents == 0
        ? labels.netHeroSettled
        : netCents < 0
            ? labels.netHeroYouOwe
            : labels.netHeroYouAreOwed;
    final accentColor = netCents < 0
        ? _coral
        : netCents > 0
            ? _jade
            : _neutral;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _mist.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SizedBox.square(
                dimension: 150,
                child: CustomPaint(
                  painter: _BalanceDonutPainter(
                    owedTotal: owedTotal,
                    owedByMe: owedByMe,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          labels.netHeroTitle,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _graphite,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            amount,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: _ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        _BalanceStatusPill(
                          label: status,
                          color: accentColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _BalanceLegend(
              labels: labels,
              owedToYouAmount: formatMoneyFromCents(owedTotal, currency),
              youOweAmount: formatMoneyFromCents(owedByMe, currency),
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.goLime,
                foregroundColor: _ink,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: canSettle ? onSettle : null,
              child: Text(
                labels.settleUp,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: _ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceStatusPill extends StatelessWidget {
  const _BalanceStatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 8,
          vertical: 3,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _BalanceLegend extends StatelessWidget {
  const _BalanceLegend({
    required this.labels,
    required this.owedToYouAmount,
    required this.youOweAmount,
  });

  final BalancesTabLabels labels;
  final String owedToYouAmount;
  final String youOweAmount;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _graphite,
          fontWeight: FontWeight.w600,
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 8,
      children: [
        _BalanceLegendItem(
          color: _jade,
          label: labels.legendOwedToYou,
          amount: owedToYouAmount,
          style: style,
        ),
        _BalanceLegendItem(
          color: _coral,
          label: labels.legendYouOwe,
          amount: youOweAmount,
          style: style,
        ),
      ],
    );
  }
}

class _BalanceLegendItem extends StatelessWidget {
  const _BalanceLegendItem({
    required this.color,
    required this.label,
    required this.amount,
    required this.style,
  });

  final Color color;
  final String label;
  final String amount;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: const SizedBox.square(dimension: 7),
        ),
        const SizedBox(width: 5),
        Text(label, style: style),
        const SizedBox(width: 4),
        Text(
          amount,
          style: style?.copyWith(
            color: _ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SettlementStatusRow extends StatelessWidget {
  const _SettlementStatusRow({
    required this.leadingMember,
    required this.fallbackName,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.amountColor,
    required this.status,
    required this.statusColor,
    required this.actions,
  });

  final TripMemberView? leadingMember;
  final String fallbackName;
  final String title;
  final String subtitle;
  final String amount;
  final Color amountColor;
  final String status;
  final Color statusColor;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final member = leadingMember;
    final displayName = member?.displayName ?? fallbackName;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CachedMemberAvatar(
                displayName: displayName,
                avatarStoragePath: member?.avatarUrl,
                avatarDisplayMode:
                    member?.avatarDisplayMode ?? AvatarDisplayMode.photo,
                avatarInitials: member?.avatarInitials,
                radius: 17,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _graphite,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 0,
                      children: actions,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: amountColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _BalanceStatusPill(
                    label: status,
                    color: statusColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberNetRow extends StatelessWidget {
  const _MemberNetRow({
    required this.member,
    required this.fallbackName,
    required this.isOwed,
    required this.amount,
    required this.labels,
  });

  final TripMemberView? member;
  final String fallbackName;
  final bool isOwed;
  final String amount;
  final BalancesTabLabels labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = member?.displayName ?? fallbackName;
    final accent = isOwed ? _jade : _coral;
    final fullLine = labels.netBalanceLine(displayName, isOwed, amount);
    final title =
        fullLine.replaceFirst(RegExp('${RegExp.escape(amount)}\$'), '').trim();
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
          child: Row(
            children: [
              CachedMemberAvatar(
                displayName: displayName,
                avatarStoragePath: member?.avatarUrl,
                avatarDisplayMode:
                    member?.avatarDisplayMode ?? AvatarDisplayMode.photo,
                avatarInitials: member?.avatarInitials,
                radius: 17,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                amount,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceDonutPainter extends CustomPainter {
  const _BalanceDonutPainter({
    required this.owedTotal,
    required this.owedByMe,
  });

  final int owedTotal;
  final int owedByMe;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = size.shortestSide * 0.12;
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = _graphite.withValues(alpha: 0.14);
    final owedPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = _jade;
    final owePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = _coral;

    final inset = strokeWidth / 2;
    final arcRect = rect.deflate(inset);
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2, false, basePaint);

    final total = owedTotal + owedByMe;
    if (total <= 0) return;
    final owedSweep = (owedTotal / total) * math.pi * 2;
    final oweSweep = (owedByMe / total) * math.pi * 2;
    canvas.drawArc(arcRect, -math.pi / 2, owedSweep, false, owedPaint);
    canvas.drawArc(
      arcRect,
      -math.pi / 2 + owedSweep + 0.08,
      math.max(0, oweSweep - 0.08),
      false,
      owePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BalanceDonutPainter oldDelegate) {
    return oldDelegate.owedTotal != owedTotal ||
        oldDelegate.owedByMe != owedByMe;
  }
}

class _SettlementRow extends StatelessWidget {
  const _SettlementRow({
    required this.display,
    required this.labels,
    required this.memberById,
    required this.isPayer,
    required this.onTap,
  });

  final SettlementDisplay display;
  final BalancesTabLabels labels;
  final Map<String, TripMemberView> memberById;
  final bool isPayer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final member = memberById[display.line.fromUserId];
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: CachedMemberAvatar(
            displayName: display.fromName,
            avatarStoragePath: member?.avatarUrl,
            avatarDisplayMode:
                member?.avatarDisplayMode ?? AvatarDisplayMode.photo,
            avatarInitials: member?.avatarInitials,
            radius: 17,
          ),
          title: Text(labels.paysLine(display.fromName, display.toName)),
          subtitle: Text(
            isPayer
                ? labels.settleUp
                : labels.waitingForPayer(display.fromName),
          ),
          trailing: Text(
            formatMoneyFromCents(display.line.cents, display.currency),
            style: theme.textTheme.titleSmall?.copyWith(
              color: isPayer ? _coral : _jade,
              fontWeight: FontWeight.w800,
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _FinalBalancesSection extends ConsumerWidget {
  const _FinalBalancesSection({
    required this.tripId,
    required this.nameById,
    required this.memberById,
    required this.currency,
    required this.labels,
  });

  final String tripId;
  final Map<String, String> nameById;
  final Map<String, TripMemberView> memberById;
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
                color: _ink,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        for (final e in nonZero)
          _MemberNetRow(
            member: memberById[e.key],
            fallbackName:
                nameById[e.key] ?? fallbackMemberDisplayName(userId: e.key),
            isOwed: e.value > 0,
            amount: formatMoneyFromCents(e.value.abs(), currency),
            labels: labels,
          ),
      ],
    );
  }
}
