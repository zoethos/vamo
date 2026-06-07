import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../balances/balances_tab.dart';
import '../balances/balances_tab_labels.dart';
import '../capture/capture_tab.dart';
import '../sync/trip_realtime_binding.dart';
import 'package:feature_split/src/expenses/trip_expense_list_tile.dart';
import '../expenses/expense_consent_providers.dart';
import '../expenses/expense_detail_sheet.dart';
import '../expenses/expense_governance.dart';
import '../expenses/expense_governance_labels.dart';
import '../expenses/trip_expenses_propose_action.dart';
import '../expenses/expenses_providers.dart';
import '../invites/invite_labels.dart';
import '../plan/plan_labels.dart';
import '../plan/plan_tab.dart';
import 'members_tab.dart';
import 'trip_home_labels.dart';
import 'trip_lifecycle_banner.dart';
import 'trip_lifecycle_actions.dart';
import 'trip_lifecycle_labels.dart';
import 'trip_lifecycle_menu.dart';
import 'trip_budget_labels.dart';
import 'trips_providers.dart';
import 'trips_repository.dart';

/// Trip hub — Expenses, Plan, Capture (solo), Balances, Members.
class TripHomeScreen extends ConsumerStatefulWidget {
  const TripHomeScreen({
    super.key,
    required this.tripId,
    this.initialTab,
    required this.inviteLabels,
    required this.planLabels,
    required this.governanceLabels,
    required this.budgetLabels,
    required this.lifecycleLabels,
    required this.tripHomeLabels,
    required this.balancesLabels,
  });

  final String tripId;

  /// Optional deep-link tab: `balances` opens the Balances tab when available.
  final String? initialTab;
  final InviteLabels inviteLabels;
  final PlanTabLabels planLabels;
  final ExpenseGovernanceLabels governanceLabels;
  final TripBudgetLabels budgetLabels;
  final TripLifecycleLabels lifecycleLabels;
  final TripHomeLabels tripHomeLabels;
  final BalancesTabLabels balancesLabels;

  @override
  ConsumerState<TripHomeScreen> createState() => _TripHomeScreenState();
}

class _TripHomeScreenState extends ConsumerState<TripHomeScreen>
    with SingleTickerProviderStateMixin {
  static const _expensesTabIndex = 0;
  static const _planTabIndex = 1;

  TabController? _tabController;
  bool _initialTabApplied = false;
  final _planTabKey = GlobalKey<PlanTabState>();
  final _membersTabKey = GlobalKey<MembersTabState>();

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
          message: widget.tripHomeLabels.loadError,
          onRetry: () => ref.invalidate(tripDetailProvider(widget.tripId)),
        ),
      ),
      data: (detail) {
        if (detail == null) {
          return Scaffold(
            appBar: AppBar(),
            body: AppEmptyState(
              screen: 'trip_home',
              icon: Icons.map_outlined,
              title: widget.tripHomeLabels.notFoundTitle,
              subtitle: widget.tripHomeLabels.notFoundSubtitle,
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
        final onCaptureTab =
            showCapture && _tabController!.index == captureTabIndex;
        final balancesTabIndex =
            showBalances ? 2 + (showCapture ? 1 : 0) : null;
        final membersTabIndex =
            2 + (showCapture ? 1 : 0) + (showBalances ? 1 : 0);
        final onExpensesTab = _tabController!.index == _expensesTabIndex;
        final onPlanTab = _tabController!.index == _planTabIndex;
        final onMembersTab = _tabController!.index == membersTabIndex;
        final readOnly = isTripReadOnly(TripLifecycle.parse(detail.lifecycle));
        final lifecycle = TripLifecycle.parse(detail.lifecycle);
        final phase = resolveTripPhase(
          lifecycle: lifecycle,
          startDateIso: detail.startDate,
          now: DateTime
              .now(), // local — date-only phase vs a date-only start (P1: UTC misclassified "today" near midnight)
        );
        final userId = ref.watch(authRepositoryProvider).currentUser?.id;
        final isOwner = userId != null && userId == detail.ownerId;
        final myMember =
            ref.watch(tripMyMemberProvider(widget.tripId)).valueOrNull;
        final menuActions = tripLifecycleMenuActions(
          phase: phase,
          isOwner: isOwner,
          memberAlreadyDone: myMember?.completedAt != null,
        );
        final repo = ref.read(tripsRepositoryProvider);

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => _navigateBack(context),
            ),
            title: Text(detail.name),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz),
                tooltip: widget.tripHomeLabels.moreMenu,
                onSelected: (value) {
                  if (value == 'settings') {
                    context.push(AppRoutes.tripSettings(widget.tripId));
                    return;
                  }
                  if (value == 'share') {
                    context.push(AppRoutes.tripSnapshot(widget.tripId));
                    return;
                  }
                  if (value.startsWith('lifecycle:')) {
                    final actionName = value.substring('lifecycle:'.length);
                    final action = TripLifecycleMenuAction.values.firstWhere(
                      (a) => a.name == actionName,
                    );
                    TripLifecycleActions.handleMenuAction(
                      context: context,
                      ref: ref,
                      tripId: widget.tripId,
                      action: action,
                      labels: widget.lifecycleLabels,
                      repo: repo,
                    );
                  }
                },
                itemBuilder: (context) => [
                  for (final action in menuActions)
                    PopupMenuItem(
                      value: 'lifecycle:${action.name}',
                      child: Text(
                        lifecycleMenuLabel(action, widget.lifecycleLabels),
                      ),
                    ),
                  if (menuActions.isNotEmpty) const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'settings',
                    child: Text(widget.tripHomeLabels.tripSettings),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: Text(widget.tripHomeLabels.shareSnapshot),
                  ),
                ],
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelPadding:
                  const EdgeInsetsDirectional.symmetric(horizontal: 4),
              tabs: [
                _TripTab(label: widget.tripHomeLabels.tabExpenses),
                _TripTab(label: widget.planLabels.tabTitle),
                if (showCapture)
                  _TripTab(label: widget.tripHomeLabels.tabCapture),
                if (showBalances)
                  _TripTab(label: widget.tripHomeLabels.tabBalances),
                _TripTab(label: widget.tripHomeLabels.tabMembers),
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
                    TripLifecycleBanner(
                      tripId: widget.tripId,
                      detail: detail,
                      labels: widget.lifecycleLabels,
                    ),
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
                      governanceLabels: widget.governanceLabels,
                      budgetLabels: widget.budgetLabels,
                    ),
                    PlanTab(
                      key: _planTabKey,
                      tripId: widget.tripId,
                      labels: widget.planLabels,
                      readOnly: readOnly,
                      showInlineAddAction: false,
                    ),
                    if (showCapture) CaptureTab(tripId: widget.tripId),
                    if (showBalances)
                      BalancesTab(
                        tripId: widget.tripId,
                        governanceLabels: widget.governanceLabels,
                        labels: widget.balancesLabels,
                      ),
                    MembersTab(
                      key: _membersTabKey,
                      tripId: widget.tripId,
                      inviteLabels: widget.inviteLabels,
                    ),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: readOnly ||
                  onCaptureTab ||
                  (balancesTabIndex != null &&
                      _tabController!.index == balancesTabIndex) ||
                  (!onPlanTab && !onExpensesTab && !onMembersTab)
              ? null
              : FloatingActionButton.extended(
                  backgroundColor: AppColors.goLime,
                  foregroundColor: AppColors.ink,
                  onPressed: () {
                    if (onPlanTab) {
                      _planTabKey.currentState?.openAddPlanItem();
                      return;
                    }
                    if (onMembersTab) {
                      _membersTabKey.currentState?.openInviteFlow();
                      return;
                    }
                    context.push(AppRoutes.tripAddExpense(widget.tripId));
                  },
                  icon: Icon(
                      onMembersTab ? Icons.person_add_outlined : Icons.add),
                  label: Text(
                    onPlanTab
                        ? widget.planLabels.addPlanItem
                        : onMembersTab
                            ? widget.inviteLabels.inviteAction
                            : widget.tripHomeLabels.addExpense,
                  ),
                ),
        );
      },
    );
  }

  void _navigateBack(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(AppRoutes.trips);
      }
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}

class _TripTab extends StatelessWidget {
  const _TripTab({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}

class _ExpensesTab extends ConsumerWidget {
  const _ExpensesTab({
    required this.tripId,
    required this.baseCurrency,
    required this.readOnly,
    required this.governanceLabels,
    required this.budgetLabels,
  });

  final String tripId;
  final String baseCurrency;
  final bool readOnly;
  final ExpenseGovernanceLabels governanceLabels;
  final TripBudgetLabels budgetLabels;

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
        final nameByUserId = members.valueOrNull == null
            ? <String, String>{}
            : {
                for (final m in members.requireValue) m.userId: m.displayName,
              };

        final consentByExpense = {
          for (final flag in consentFlags)
            flag.expenseId: governanceLabels.consentDisplayLabel(
              memberName:
                  nameByUserId[flag.userId] ?? governanceLabels.someoneFallback,
              response: flag.response,
            ),
        };

        if (list.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                      governanceLabels.someoneFallback;
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
                    proposalRowPrefix: governanceLabels.proposalRowPrefix,
                    onTap: () => showExpenseDetailSheet(
                      context: context,
                      ref: ref,
                      expense: e,
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
