import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../capture/capture_action_sheet.dart';
import '../expenses/expenses_providers.dart';
import '../sync/trip_realtime_binding.dart';
import 'trip_dashboard_tab.dart';
import 'trip_home_labels.dart';
import 'trip_lifecycle_actions.dart';
import 'trip_lifecycle_labels.dart';
import 'trip_lifecycle_menu.dart';
import 'trips_models.dart';
import 'trips_providers.dart';
import 'trips_repository.dart';

/// Trip hub — dashboard overview with quick-actions into section routes.
class TripHomeScreen extends ConsumerStatefulWidget {
  const TripHomeScreen({
    super.key,
    required this.tripId,
    this.initialTab,
    required this.lifecycleLabels,
    required this.tripHomeLabels,
  });

  final String tripId;

  /// Optional deep-link tab: `balances` opens the balances section when available.
  final String? initialTab;
  final TripLifecycleLabels lifecycleLabels;
  final TripHomeLabels tripHomeLabels;

  @override
  ConsumerState<TripHomeScreen> createState() => _TripHomeScreenState();
}

class _TripHomeScreenState extends ConsumerState<TripHomeScreen> {
  bool _initialTabApplied = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(tripRealtimeBindingProvider(widget.tripId));

    final trip = ref.watch(tripDetailProvider(widget.tripId));
    final members = ref.watch(tripMembersForExpenseProvider(widget.tripId));

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

        return members.when(
          loading: () => _buildTripHomeScaffold(
            context: context,
            ref: ref,
            detail: detail,
            readOnly: isTripReadOnly(TripLifecycle.parse(detail.lifecycle)),
            showBalances: false,
            menuActions: const [],
            repo: ref.read(tripsRepositoryProvider),
            lifecycle: TripLifecycle.parse(detail.lifecycle),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: AppErrorState(
              screen: 'trip_home',
              message: widget.tripHomeLabels.loadError,
              onRetry: () =>
                  ref.invalidate(tripMembersForExpenseProvider(widget.tripId)),
            ),
          ),
          data: (memberList) {
            final showBalances = memberList.length > 1;

            if (!_initialTabApplied &&
                widget.initialTab == 'balances' &&
                showBalances) {
              _initialTabApplied = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                context.go(AppRoutes.tripBalances(widget.tripId));
              });
            }

            final readOnly =
                isTripReadOnly(TripLifecycle.parse(detail.lifecycle));
            final lifecycle = TripLifecycle.parse(detail.lifecycle);
            final phase = resolveTripPhase(
              lifecycle: lifecycle,
              startDateIso: detail.startDate,
              now: DateTime.now(),
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

            return _buildTripHomeScaffold(
              context: context,
              ref: ref,
              detail: detail,
              readOnly: readOnly,
              showBalances: showBalances,
              menuActions: menuActions,
              repo: repo,
              lifecycle: lifecycle,
            );
          },
        );
      },
    );
  }

  Widget _buildTripHomeScaffold({
    required BuildContext context,
    required WidgetRef ref,
    required TripDetail detail,
    required bool readOnly,
    required bool showBalances,
    required List<TripLifecycleMenuAction> menuActions,
    required TripsRepository repo,
    required TripLifecycle lifecycle,
    Widget? body,
  }) {
    final showCloseReport = lifecycle == TripLifecycle.closing ||
        lifecycle == TripLifecycle.closed ||
        lifecycle == TripLifecycle.unresolved;

    final dashboard = body ??
        TripDashboardTab(
          tripId: widget.tripId,
          detail: detail,
          labels: widget.tripHomeLabels,
          lifecycleLabels: widget.lifecycleLabels,
          readOnly: readOnly,
          showBalances: showBalances,
          onCapture: readOnly
              ? null
              : () => showCaptureActionSheet(
                    context: context,
                    tripId: widget.tripId,
                  ),
          onExpenses: () => context.push(AppRoutes.tripExpenses(widget.tripId)),
          onPlans: () => context.push(AppRoutes.tripPlan(widget.tripId)),
          onBalances: () => context.push(AppRoutes.tripBalances(widget.tripId)),
          onMembers: () => context.push(AppRoutes.tripMembers(widget.tripId)),
          onMemories: () => context.push(AppRoutes.tripMemories(widget.tripId)),
          onInvite: () => context.push(AppRoutes.tripMembers(widget.tripId)),
        );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => _navigateBack(context),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: Colors.white),
              color: context.vamoColors.surface,
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
                if (value == 'close_report') {
                  context.push(AppRoutes.tripCloseReport(widget.tripId));
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
                if (showCloseReport)
                  PopupMenuItem(
                    value: 'close_report',
                    child: Text(widget.tripHomeLabels.closeReport),
                  ),
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
        ),
        body: dashboard,
      ),
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
