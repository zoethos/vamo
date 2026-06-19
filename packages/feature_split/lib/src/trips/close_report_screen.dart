import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../balances/balances_providers.dart';
import '../expenses/expense_consent_providers.dart';
import '../expenses/expense_governance_labels.dart';
import '../expenses/expenses_providers.dart';
import '../expenses/money_format.dart';
import 'cached_member_avatar.dart';
import 'close_report_labels.dart';
import 'close_report_models.dart';
import 'trips_providers.dart';

/// Read-only close statement for closing/closed/unresolved trips (S22).
class CloseReportScreen extends ConsumerWidget {
  const CloseReportScreen({
    super.key,
    required this.tripId,
    required this.labels,
    required this.governanceLabels,
  });

  final String tripId;
  final CloseReportLabels labels;
  final ExpenseGovernanceLabels governanceLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(tripDetailProvider(tripId));
    final members = ref.watch(tripActiveMembersProvider(tripId));
    final balances = ref.watch(tripNetBalancesProvider(tripId));
    final expenseMembers = ref.watch(tripMembersForExpenseProvider(tripId));
    final consentFlags = ref.watch(tripShareConsentFlagsProvider(tripId));
    final now = DateTime.now().toUtc();

    return detail.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text(labels.title)),
        body: AppErrorState(
          screen: 'close_report',
          message: labels.loadError,
          onRetry: () => ref.invalidate(tripDetailProvider(tripId)),
        ),
      ),
      data: (trip) {
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(title: Text(labels.title)),
            body: Center(child: Text(labels.notAvailable)),
          );
        }
        final lifecycle = TripLifecycle.parse(trip.lifecycle);
        if (lifecycle != TripLifecycle.closing &&
            lifecycle != TripLifecycle.closed &&
            lifecycle != TripLifecycle.unresolved) {
          return Scaffold(
            appBar: AppBar(title: Text(labels.title)),
            body: Center(child: Text(labels.notAvailable)),
          );
        }

        final nameById = expenseMembers.valueOrNull == null
            ? <String, String>{}
            : {
                for (final m in expenseMembers.requireValue)
                  m.userId: m.displayName,
              };

        return Scaffold(
          appBar: AppBar(
            title: Text(labels.title),
            leading: BackButton(
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  context.go(AppRoutes.trip(tripId));
                }
              },
            ),
          ),
          body: members.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AppErrorState(
              screen: 'close_report',
              message: labels.loadError,
              onRetry: () => ref.invalidate(tripActiveMembersProvider(tripId)),
            ),
            data: (memberRows) {
              final disputedLabels = consentFlags
                  .map(
                    (f) => governanceLabels.consentDisplayLabel(
                      memberName: nameById[f.userId] ??
                          fallbackMemberDisplayName(userId: f.userId),
                      response: f.response,
                    ),
                  )
                  .where((label) => label.isNotEmpty)
                  .toList(growable: false);

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    trip.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    labels.balancesTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  balances.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => Text(labels.loadError),
                    data: (data) {
                      if (data.nets.isEmpty) {
                        return Text(labels.noBalances);
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: data.nets.entries.map((entry) {
                          final name = nameById[entry.key] ??
                              fallbackMemberDisplayName(userId: entry.key);
                          final amount = formatMoneyFromCents(
                            entry.value.abs(),
                            data.currency,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              labels.balanceLine(
                                name,
                                entry.value > 0,
                                amount,
                              ),
                              style: TextStyle(
                                color: entry.value > 0
                                    ? AppColors.jadeTeal
                                    : AppColors.coralText,
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    labels.membersTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ...memberRows.map((member) {
                    final displayName = fallbackMemberDisplayName(
                      userId: member.userId,
                      displayName:
                          member.displayName ?? nameById[member.userId],
                    );
                    final consent = resolveCloseMemberConsent(
                      closeAcceptedAt: member.closeAcceptedAt,
                      closeObjectedAt: member.closeObjectedAt,
                      closeNotifiedAt: member.closeNotifiedAt,
                      lifecycle: lifecycle,
                      now: now,
                    );
                    final consentLabel = switch (consent) {
                      CloseMemberConsentDisplay.accepted =>
                        labels.consentAccepted,
                      CloseMemberConsentDisplay.objected =>
                        labels.consentObjected,
                      CloseMemberConsentDisplay.deemed => labels.consentDeemed,
                      CloseMemberConsentDisplay.pending =>
                        labels.consentPending,
                      CloseMemberConsentDisplay.notNotified =>
                        labels.consentNotNotified,
                    };
                    final consentColor = switch (consent) {
                      CloseMemberConsentDisplay.accepted => AppColors.jadeTeal,
                      CloseMemberConsentDisplay.objected => AppColors.coralText,
                      CloseMemberConsentDisplay.deemed => AppColors.graphite,
                      CloseMemberConsentDisplay.pending => AppColors.deepPlum,
                      CloseMemberConsentDisplay.notNotified =>
                        AppColors.coralText,
                    };
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CachedMemberAvatar(
                        displayName: displayName,
                        avatarStoragePath: member.avatarUrl,
                        radius: 20,
                      ),
                      title: Text(displayName),
                      subtitle: Text(
                        consentLabel,
                        style: TextStyle(color: consentColor),
                      ),
                    );
                  }),
                  if (disputedLabels.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      labels.disputedTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...disputedLabels.map(
                      (label) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          label,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.coralText),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }
}
