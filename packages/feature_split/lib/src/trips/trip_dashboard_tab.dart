import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../expenses/expense_governance.dart';
import '../expenses/expense_models.dart';
import '../expenses/expenses_providers.dart';
import '../expenses/money_format.dart';
import 'dashboard_activity_row.dart';
import 'member_avatar_row.dart';
import 'trip_format.dart';
import 'trip_home_labels.dart';
import 'trip_lifecycle_banner.dart';
import 'trip_lifecycle_labels.dart';
import 'trip_visual_backdrop.dart';
import 'trips_models.dart';
import 'trips_providers.dart';

/// Trip landing dashboard — S35 fidelity layout on gradient fallback.
class TripDashboardTab extends ConsumerWidget {
  const TripDashboardTab({
    super.key,
    required this.tripId,
    required this.detail,
    required this.labels,
    required this.lifecycleLabels,
    required this.readOnly,
    required this.showBalances,
    this.onCapture,
    required this.onExpenses,
    required this.onPlans,
    required this.onBalances,
    required this.onMembers,
    required this.onMemories,
    required this.onInvite,
  });

  final String tripId;
  final TripDetail detail;
  final TripHomeLabels labels;
  final TripLifecycleLabels lifecycleLabels;
  final bool readOnly;
  final bool showBalances;
  final ValueChanged<LayerLink>? onCapture;
  final VoidCallback onExpenses;
  final VoidCallback onPlans;
  final VoidCallback onBalances;
  final VoidCallback onMembers;
  final VoidCallback onMemories;
  final VoidCallback onInvite;

  /// Estimated card height for hero overlap (top ~1/3 sits on the hero).
  static const _totalCardEstHeight = 104.0;
  static const _cardHeroOverlapFraction = 0.33;
  static const _avatarRowHeight = 40.0;
  static const _heroTitleEstHeight = 56.0;
  static const _heroDatesEstHeight = 20.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;
    final shape = context.vamoShape;
    final expenses = ref.watch(tripExpensesProvider(tripId));
    final members = ref.watch(tripMembersForExpenseProvider(tripId));
    final dates = formatTripDateRange(detail.startDate, detail.endDate);
    final cardHeroOverlap = _totalCardEstHeight * _cardHeroOverlapFraction;
    final heroTopInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final heroContentHeight = space.x2 +
        _heroTitleEstHeight +
        (dates != null ? space.x2 + _heroDatesEstHeight : 0) +
        space.x2 +
        _avatarRowHeight +
        space.x3;
    final heroBackgroundHeight =
        heroTopInset + heroContentHeight + cardHeroOverlap;
    final heroBackgroundPath = ref.watch(tripHeroBackgroundProvider(tripId));
    final phase = resolveTripPhase(
      lifecycle: TripLifecycle.parse(detail.lifecycle),
      startDateIso: detail.startDate,
      now: DateTime.now(),
    );
    final showLifecycleBanner =
        phase == TripPhase.closing || phase == TripPhase.readOnly;

    Widget totalSpentCard(List<ExpenseSummary> list) {
      final active = list
          .where((e) => e.status != ExpenseStatus.cancelled)
          .toList(growable: false);
      final totalCents = active.fold<int>(0, (sum, e) => sum + e.baseCents);
      final memberCount = members.valueOrNull?.length;
      final perPerson = memberCount != null && memberCount > 0
          ? totalCents ~/ memberCount
          : 0;
      final slices = buildCategoryDonutSlices(
        rows: active.map((e) => (category: e.category, cents: e.baseCents)),
        totalCents: totalCents,
      );
      return _TotalSpentCard(
        shape: shape,
        colors: colors,
        type: type,
        totalLabel: labels.totalSpentLabel,
        totalAmount: formatMoneyFromCents(totalCents, detail.baseCurrency),
        perPersonLabel: memberCount != null && memberCount > 1
            ? labels.perPersonLabel(
                formatMoneyFromCents(perPerson, detail.baseCurrency),
              )
            : null,
        slices: slices,
      );
    }

    return ListView(
      padding: EdgeInsetsDirectional.only(bottom: space.x4),
      children: [
        _TripDashboardHeroSection(
          heroBackgroundHeight: heroBackgroundHeight,
          cardHeroOverlap: cardHeroOverlap,
          heroTopInset: heroTopInset,
          backgroundImagePath: heroBackgroundPath,
          onCapture: onCapture,
          readOnly: readOnly,
          labels: labels,
          colors: colors,
          detail: detail,
          dates: dates,
          type: type,
          space: space,
          avatarRow: members.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (rows) => MemberAvatarRow(
              members: rows,
              onAdd: readOnly ? () {} : onInvite,
            ),
          ),
          card: expenses.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => _TotalSpentCard(
              shape: shape,
              colors: colors,
              type: type,
              totalLabel: labels.totalSpentLabel,
              totalAmount: formatMoneyFromCents(0, detail.baseCurrency),
              perPersonLabel: null,
              slices: const [],
            ),
            data: totalSpentCard,
          ),
        ),
        if (showLifecycleBanner) ...[
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              space.x4,
              space.x3,
              space.x4,
              0,
            ),
            child: TripLifecycleBanner(
              tripId: tripId,
              detail: detail,
              labels: lifecycleLabels,
            ),
          ),
          SizedBox(height: space.x3),
        ],
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            space.x4,
            showLifecycleBanner ? 0 : space.x3,
            space.x4,
            0,
          ),
          child: _QuickActionsRow(
            labels: labels,
            showBalances: showBalances,
            onExpenses: onExpenses,
            onPlans: onPlans,
            onBalances: onBalances,
            onMembers: onMembers,
            onMemories: onMemories,
          ),
        ),
        SizedBox(height: space.x4),
        Padding(
          padding: EdgeInsetsDirectional.symmetric(horizontal: space.x4),
          child: Text(
            labels.recentActivity,
            style: type.titleSmall.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(height: space.x2),
        expenses.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (list) {
            final recent = list
                .where((e) => e.status != ExpenseStatus.cancelled)
                .toList(growable: false)
              ..sort((a, b) => b.spentAt.compareTo(a.spentAt));
            final top = recent.take(5).toList(growable: false);
            if (top.isEmpty) {
              return Padding(
                padding: EdgeInsetsDirectional.symmetric(horizontal: space.x4),
                child: Text(
                  labels.noRecentActivity,
                  style: type.bodyMedium.copyWith(color: colors.onSurfaceMuted),
                ),
              );
            }
            return Column(
              children: [
                for (final expense in top)
                  DashboardActivityRow(
                    description: expense.description,
                    category: expense.category,
                    amount: formatMoneyFromCents(
                      expense.baseCents,
                      detail.baseCurrency,
                    ),
                    occurredAt: expense.spentAt,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TripDashboardHeroSection extends StatefulWidget {
  const _TripDashboardHeroSection({
    required this.heroBackgroundHeight,
    required this.cardHeroOverlap,
    required this.heroTopInset,
    required this.backgroundImagePath,
    required this.onCapture,
    required this.readOnly,
    required this.labels,
    required this.colors,
    required this.detail,
    required this.dates,
    required this.type,
    required this.space,
    required this.avatarRow,
    required this.card,
  });

  final double heroBackgroundHeight;
  final double cardHeroOverlap;
  final double heroTopInset;
  final String? backgroundImagePath;
  final ValueChanged<LayerLink>? onCapture;
  final bool readOnly;
  final TripHomeLabels labels;
  final VamoSemanticColors colors;
  final TripDetail detail;
  final String? dates;
  final VamoTypeScale type;
  final VamoSpacing space;
  final Widget avatarRow;
  final Widget card;

  @override
  State<_TripDashboardHeroSection> createState() =>
      _TripDashboardHeroSectionState();
}

class _TripDashboardHeroSectionState extends State<_TripDashboardHeroSection> {
  final GlobalKey _cardKey = GlobalKey();
  final LayerLink _captureAnchorLink = LayerLink();
  double _cardHeight = TripDashboardTab._totalCardEstHeight;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final height = _cardKey.currentContext?.size?.height;
      if (height != null && (height - _cardHeight).abs() > 0.5) {
        setState(() => _cardHeight = height);
      }
    });

    final headerHeight =
        widget.heroBackgroundHeight - widget.cardHeroOverlap + _cardHeight;

    return SizedBox(
      height: headerHeight,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: widget.heroBackgroundHeight,
            child: TripVisualBackdrop(
              tripName: widget.detail.name,
              destination: widget.detail.destination,
              backgroundImagePath: widget.backgroundImagePath,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const GradientScrim(heightFactor: 0.85),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: widget.heroTopInset + widget.space.x6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: AlignmentDirectional.topCenter,
                          end: AlignmentDirectional.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.55),
                            Colors.black.withValues(alpha: 0.2),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                  if (widget.onCapture != null && !widget.readOnly)
                    PositionedDirectional(
                      top: widget.heroTopInset + widget.space.x2,
                      end: widget.space.x2,
                      child: CompositedTransformTarget(
                        link: _captureAnchorLink,
                        child: VamoCircleIcon(
                          diameter: 48,
                          backgroundColor: Colors.white,
                          shadow: true,
                          onTap: () =>
                              widget.onCapture?.call(_captureAnchorLink),
                          tooltip: widget.labels.tabCapture,
                          child: Icon(
                            Icons.camera_alt_outlined,
                            color: widget.colors.secondary,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          PositionedDirectional(
            start: widget.space.x4,
            end: widget.space.x4,
            bottom: _cardHeight + widget.space.x3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.detail.name,
                  style: widget.type.display.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.dates != null) ...[
                  SizedBox(height: widget.space.x2),
                  Text(
                    widget.dates!,
                    style: widget.type.bodyMedium.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
                SizedBox(height: widget.space.x2),
                widget.avatarRow,
              ],
            ),
          ),
          PositionedDirectional(
            start: widget.space.x4,
            end: widget.space.x4,
            top: widget.heroBackgroundHeight - widget.cardHeroOverlap,
            child: KeyedSubtree(key: _cardKey, child: widget.card),
          ),
        ],
      ),
    );
  }
}

class _TotalSpentCard extends StatelessWidget {
  const _TotalSpentCard({
    required this.shape,
    required this.colors,
    required this.type,
    required this.totalLabel,
    required this.totalAmount,
    required this.perPersonLabel,
    required this.slices,
  });

  final VamoRadiusElevation shape;
  final VamoSemanticColors colors;
  final VamoTypeScale type;
  final String totalLabel;
  final String totalAmount;
  final String? perPersonLabel;
  final List<CategoryDonutSlice> slices;

  @override
  Widget build(BuildContext context) {
    final space = context.vamoSpace;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: shape.cardBorderRadius,
        border: Border.all(color: colors.divider.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.all(space.x4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    totalLabel,
                    style: type.labelMedium.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                  SizedBox(height: space.x1),
                  Text(
                    totalAmount,
                    style: type.headline.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (perPersonLabel != null) ...[
                    SizedBox(height: space.x1),
                    Text(
                      perPersonLabel!,
                      style: type.bodySmall.copyWith(
                        color: colors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            CategoryDonut(slices: slices),
          ],
        ),
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.labels,
    required this.showBalances,
    required this.onExpenses,
    required this.onPlans,
    required this.onBalances,
    required this.onMembers,
    required this.onMemories,
  });

  static const _tileExtent = 76.0;

  final TripHomeLabels labels;
  final bool showBalances;
  final VoidCallback onExpenses;
  final VoidCallback onPlans;
  final VoidCallback onBalances;
  final VoidCallback onMembers;
  final VoidCallback onMemories;

  @override
  Widget build(BuildContext context) {
    final space = context.vamoSpace;
    final actions = [
      _QuickActionTile(
        icon: Icons.receipt_long_outlined,
        label: labels.quickExpenses,
        onTap: onExpenses,
      ),
      _QuickActionTile(
        icon: Icons.event_outlined,
        label: labels.quickPlans,
        onTap: onPlans,
      ),
      if (showBalances)
        _QuickActionTile(
          icon: Icons.account_balance_wallet_outlined,
          label: labels.quickBalances,
          onTap: onBalances,
        ),
      _QuickActionTile(
        icon: Icons.people_outline,
        label: labels.quickMembers,
        onTap: onMembers,
      ),
      _QuickActionTile(
        icon: Icons.photo_library_outlined,
        label: labels.quickMemories,
        onTap: onMemories,
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) SizedBox(width: space.x2),
            SizedBox(
              width: _tileExtent,
              height: _tileExtent,
              child: actions[i],
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final shape = context.vamoShape;
    final space = context.vamoSpace;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: shape.controlBorderRadius,
        border: Border.all(color: colors.divider.withValues(alpha: 0.6)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: shape.controlBorderRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape.controlBorderRadius,
          child: Padding(
            padding: EdgeInsetsDirectional.all(space.x2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: colors.secondary, size: 24),
                SizedBox(height: space.x1),
                Text(
                  label,
                  style: type.labelSmall.copyWith(color: colors.onSurface),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
