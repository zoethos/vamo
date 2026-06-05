import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../balances/balances_tab.dart';
import '../capture/capture_tab.dart';
import '../sync/trip_realtime_binding.dart';
import 'package:feature_split/src/expenses/trip_expense_list_tile.dart';
import '../expenses/expense_consent_providers.dart';
import '../expenses/expense_detail_sheet.dart';
import '../expenses/expense_governance.dart';
import '../expenses/expenses_providers.dart';
import '../invites/invite_labels.dart';
import '../signals/coming_soon_teaser.dart';
import '../plan/plan_labels.dart';
import '../plan/plan_tab.dart';
import 'members_tab.dart';
import 'trip_lifecycle_banner.dart';
import 'trips_models.dart';
import 'trips_providers.dart';

/// Trip hub — Expenses, Plan, Capture (solo), Balances, Members.
class TripHomeScreen extends ConsumerStatefulWidget {
  const TripHomeScreen({
    super.key,
    required this.tripId,
    this.initialTab,
    required this.inviteLabels,
    required this.planLabels,
  });

  final String tripId;

  /// Optional deep-link tab: `balances` opens the Balances tab when available.
  final String? initialTab;
  final InviteLabels inviteLabels;
  final PlanTabLabels planLabels;

  @override
  ConsumerState<TripHomeScreen> createState() => _TripHomeScreenState();
}

class _TripHomeScreenState extends ConsumerState<TripHomeScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  bool _initialTabApplied = false;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tripRealtimeBindingProvider(widget.tripId));

    final trip = ref.watch(tripDetailProvider(widget.tripId));
    final memberCount = ref.watch(tripMemberCountProvider(widget.tripId));

    return trip.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: AppErrorState(
          screen: 'trip_home',
          message: 'Could not load this trip.',
          onRetry: () => ref.invalidate(tripDetailProvider(widget.tripId)),
        ),
      ),
      data: (detail) {
        if (detail == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const AppEmptyState(
              screen: 'trip_home',
              icon: Icons.map_outlined,
              title: 'Trip not found',
              subtitle: 'It may have been removed or you no longer have access.',
            ),
          );
        }
        final count = memberCount.valueOrNull ?? 1;
        final showBalances = count > 1;
        final showCapture = !showBalances;

        final tabCount = 3 + (showCapture ? 1 : 0) + (showBalances ? 1 : 0);
        if (_tabController == null || _tabController!.length != tabCount) {
          _tabController?.dispose();
          _tabController = TabController(length: tabCount, vsync: this)
            ..addListener(() {
              if (mounted) setState(() {});
            });
          _initialTabApplied = false;
        }

        if (!_initialTabApplied &&
            widget.initialTab == 'balances' &&
            showBalances) {
          _initialTabApplied = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _tabController == null) return;
            _tabController!.index = showCapture ? 3 : 2;
          });
        }

        final captureTabIndex = 2;
        final hideExpenseFab =
            showCapture && _tabController!.index == captureTabIndex;
        final postTrip = _isPostTrip(detail);
        final readOnly = isTripReadOnly(TripLifecycle.parse(detail.lifecycle));

        return Scaffold(
          appBar: AppBar(
            title: Text(detail.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Share snapshot',
                onPressed: () =>
                    context.push(AppRoutes.tripSnapshot(widget.tripId)),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: [
                const Tab(text: 'Expenses'),
                Tab(text: widget.planLabels.tabTitle),
                if (showCapture) const Tab(text: 'Capture'),
                if (showBalances) const Tab(text: 'Balances'),
                const Tab(text: 'Members'),
              ],
            ),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
                child: Column(
                  children: [
                    TripLifecycleBanner(tripId: widget.tripId, detail: detail),
                    const SizedBox(height: 8),
                    ComingSoonTeaser(
                      interestEvent: VamoEvent.mapInterestTapped,
                      feature: 'map',
                      title: 'Trip map — coming soon',
                      icon: Icons.map_outlined,
                    ),
                    if (postTrip) ...[
                      const SizedBox(height: 8),
                      ComingSoonTeaser(
                        interestEvent: VamoEvent.recapInterestTapped,
                        feature: 'recap',
                        title: 'Trip recap video — coming soon',
                        icon: Icons.movie_filter_outlined,
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _ExpensesTab(
                      tripId: widget.tripId,
                      baseCurrency: detail.baseCurrency,
                      readOnly: readOnly,
                    ),
                    PlanTab(
                      tripId: widget.tripId,
                      labels: widget.planLabels,
                      readOnly: readOnly,
                    ),
                    if (showCapture) CaptureTab(tripId: widget.tripId),
                    if (showBalances) BalancesTab(tripId: widget.tripId),
                    MembersTab(
                      tripId: widget.tripId,
                      inviteLabels: widget.inviteLabels,
                    ),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: hideExpenseFab || readOnly
              ? null
              : FloatingActionButton.extended(
                  backgroundColor: AppColors.goLime,
                  foregroundColor: AppColors.ink,
                  onPressed: () =>
                      context.push(AppRoutes.tripAddExpense(widget.tripId)),
                  icon: const Icon(Icons.add),
                  label: const Text('Add expense'),
                ),
        );
      },
    );
  }

  bool _isPostTrip(TripDetail detail) {
    final end = detail.endDate;
    if (end == null) return false;
    final parsed = DateTime.tryParse(end);
    if (parsed == null) return false;
    final today = DateTime.now();
    final endDay = DateTime(parsed.year, parsed.month, parsed.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    return endDay.isBefore(todayDay);
  }
}

class _ExpensesTab extends ConsumerWidget {
  const _ExpensesTab({
    required this.tripId,
    required this.baseCurrency,
    required this.readOnly,
  });

  final String tripId;
  final String baseCurrency;
  final bool readOnly;

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

    return expenses.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorState(
        screen: 'trip_expenses',
        message: 'Could not load expenses.',
        onRetry: () => ref.invalidate(tripExpensesProvider(tripId)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const AppEmptyState(
            screen: 'trip_expenses',
            icon: Icons.receipt_long_outlined,
            title: 'No expenses yet',
            subtitle: 'Tap Add expense to log your first cost.',
          );
        }

        final nameByUserId = members.valueOrNull == null
            ? <String, String>{}
            : {
                for (final m in members.requireValue) m.userId: m.displayName,
              };

        final consentByExpense = {
          for (final flag in consentFlags) flag.expenseId: flag.label,
        };

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final e = list[i];
            if (e.status == ExpenseStatus.cancelled) {
              return const SizedBox.shrink();
            }
            final payer = nameByUserId[e.payerId] ?? 'Someone';
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
              status: e.status,
              consentLabel: consentByExpense[e.id],
              onTap: () => showExpenseDetailSheet(
                context: context,
                ref: ref,
                expense: e,
                readOnly: readOnly,
                canManageProposals: canManageProposals,
              ),
            );
          },
        );
      },
    );
  }
}
