import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../invites/invite_flow.dart';
import '../notifications/notifications_providers.dart';
import '../weather/weather_labels.dart';
import 'compact_trip_card.dart';
import 'featured_trip_card.dart';
import 'trip_format.dart';
import 'trip_list_layout.dart';
import 'trips_models.dart';
import 'trips_providers.dart';

enum TripListFilter { all, upcoming, past, drafts }

class TripsListScreenLabels {
  const TripsListScreenLabels({
    required this.title,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.emptyUpcomingTitle,
    required this.emptyPastTitle,
    required this.syncPendingLabel,
    required this.syncSubtitle,
    required this.filterAll,
    required this.filterUpcoming,
    required this.filterPast,
    required this.filterDrafts,
    required this.loadError,
    required this.syncError,
    required this.sectionUpcoming,
    required this.sectionPast,
    required this.participants,
    required this.notificationsTooltip,
    required this.notificationsUnreadBadge,
    required this.createTripTooltip,
    required this.weather,
  });

  final String title;
  final String emptyTitle;
  final String emptySubtitle;
  final String emptyUpcomingTitle;
  final String emptyPastTitle;
  final String Function(int count) syncPendingLabel;
  final String syncSubtitle;
  final String filterAll;
  final String filterUpcoming;
  final String filterPast;
  final String filterDrafts;
  final String loadError;
  final String syncError;
  final String sectionUpcoming;
  final String sectionPast;
  final String Function(int count) participants;
  final String notificationsTooltip;
  final String Function(int count) notificationsUnreadBadge;
  final String createTripTooltip;
  final WeatherBadgeLabels weather;
}

class TripsListScreen extends ConsumerStatefulWidget {
  const TripsListScreen({super.key, required this.labels});

  final TripsListScreenLabels labels;

  @override
  ConsumerState<TripsListScreen> createState() => _TripsListScreenState();
}

class _TripsListScreenState extends ConsumerState<TripsListScreen> {
  TripListFilter _filter = TripListFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.invalidate(tripsSyncProvider);
      await tryConsumePendingInvite(ref: ref, context: context);
    });
  }

  List<TripSummary> _filtered(List<TripSummary> list) {
    final now = DateTime.now();
    return switch (_filter) {
      TripListFilter.all => list,
      TripListFilter.drafts => const [],
      TripListFilter.upcoming => list.where((t) {
          final start = parseTripDate(t.startDate);
          return start != null && start.isAfter(now);
        }).toList(growable: false),
      TripListFilter.past => list.where((t) {
          final end = parseTripDate(t.endDate) ?? parseTripDate(t.startDate);
          return end != null && end.isBefore(now);
        }).toList(growable: false),
    };
  }

  String _emptyTitle({required List<TripSummary> allTrips}) {
    if (allTrips.isEmpty && _filter == TripListFilter.all) {
      return widget.labels.emptyTitle;
    }
    return switch (_filter) {
      TripListFilter.all => widget.labels.emptyTitle,
      TripListFilter.upcoming => widget.labels.emptyUpcomingTitle,
      TripListFilter.past => widget.labels.emptyPastTitle,
      TripListFilter.drafts => widget.labels.emptyPastTitle,
    };
  }

  Widget _buildTripList({
    required List<TripSummary> filtered,
    required int pendingSync,
  }) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;

    final layout = layoutTripsForMyTrips(filtered);
    final showHierarchy =
        _filter == TripListFilter.all || _filter == TripListFilter.upcoming;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsetsDirectional.fromSTEB(
        space.x4,
        0,
        space.x4,
        space.x4,
      ),
      children: [
        if (pendingSync > 0) ...[
          _SyncBanner(
            count: pendingSync,
            labels: widget.labels,
            onTap: () => ref.invalidate(tripsSyncProvider),
          ),
          SizedBox(height: space.x3),
        ],
        if (showHierarchy && layout.hasFeatured) ...[
          FeaturedTripCard(
            trip: layout.featured!,
            participantsLabel: widget.labels.participants,
            weatherLabels: widget.labels.weather,
          ),
          if (layout.upcoming.isNotEmpty) ...[
            SizedBox(height: space.x4),
            Text(
              widget.labels.sectionUpcoming,
              style: type.titleSmall.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: space.x2),
          ],
        ],
        if (showHierarchy) ...[
          for (final trip in layout.upcoming) ...[
            CompactTripCard(
              trip: trip,
              participantsLabel: widget.labels.participants,
              weatherLabels: widget.labels.weather,
            ),
            SizedBox(height: space.x2),
          ],
          if (_filter == TripListFilter.all && layout.past.isNotEmpty) ...[
            SizedBox(height: space.x2),
            Text(
              widget.labels.sectionPast,
              style: type.titleSmall.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: space.x2),
            for (final trip in layout.past) ...[
              CompactTripCard(
                trip: trip,
                participantsLabel: widget.labels.participants,
                weatherLabels: widget.labels.weather,
              ),
              SizedBox(height: space.x2),
            ],
          ],
          if (_filter == TripListFilter.all && layout.other.isNotEmpty)
            for (final trip in layout.other) ...[
              CompactTripCard(
                trip: trip,
                participantsLabel: widget.labels.participants,
                weatherLabels: widget.labels.weather,
              ),
              SizedBox(height: space.x2),
            ],
        ] else
          _FlatCompactList(
            trips: filtered,
            participantsLabel: widget.labels.participants,
            weatherLabels: widget.labels.weather,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;
    final sync = ref.watch(tripsSyncProvider);
    final trips = ref.watch(tripsListProvider);
    final pendingSync = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              BrandAssets.primaryMark,
              height: 28,
            ),
            SizedBox(width: space.x3),
            Expanded(
              child: Text(
                widget.labels.title,
                style: type.titleMedium.copyWith(color: colors.onBackground),
              ),
            ),
          ],
        ),
        actions: [
          _NotificationsBell(labels: widget.labels),
          SizedBox(width: space.x1),
          IconButton(
            tooltip: widget.labels.createTripTooltip,
            icon: const Icon(Icons.add),
            onPressed: () => context.push(AppRoutes.tripCreate),
          ),
        ],
      ),
      body: sync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorState(
          screen: 'trips_list',
          kind: AnalyticsErrorKind.network,
          message: widget.labels.syncError,
          onRetry: () => ref.invalidate(tripsSyncProvider),
        ),
        data: (_) => trips.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AppErrorState(
            screen: 'trips_list',
            message: widget.labels.loadError,
            onRetry: () => ref.invalidate(tripsListProvider),
          ),
          data: (list) {
            final filtered = _filtered(list);
            final globalEmpty = list.isEmpty;
            final filterEmpty = filtered.isEmpty;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    space.x4,
                    space.x3,
                    space.x4,
                    0,
                  ),
                  child: _FilterRow(
                    key: const Key('trips_filter_row'),
                    labels: widget.labels,
                    filter: _filter,
                    showDraftsFilter: false,
                    onFilterChanged: (f) => setState(() => _filter = f),
                  ),
                ),
                Expanded(
                  child: filterEmpty
                      ? AppEmptyState(
                          screen: 'trips_list',
                          icon: Icons.airport_shuttle_outlined,
                          title: _emptyTitle(allTrips: list),
                          subtitle: globalEmpty && _filter == TripListFilter.all
                              ? widget.labels.emptySubtitle
                              : null,
                          useBrandMark:
                              globalEmpty && _filter == TripListFilter.all,
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            ref.invalidate(tripsSyncProvider);
                            await ref.read(tripsSyncProvider.future);
                          },
                          child: _buildTripList(
                            filtered: filtered,
                            pendingSync: pendingSync,
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    super.key,
    required this.labels,
    required this.filter,
    required this.onFilterChanged,
    this.showDraftsFilter = false,
  });

  final TripsListScreenLabels labels;
  final TripListFilter filter;
  final ValueChanged<TripListFilter> onFilterChanged;
  final bool showDraftsFilter;

  @override
  Widget build(BuildContext context) {
    final space = context.vamoSpace;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterPill(
            label: labels.filterAll,
            selected: filter == TripListFilter.all,
            onTap: () => onFilterChanged(TripListFilter.all),
          ),
          SizedBox(width: space.x2),
          _FilterPill(
            label: labels.filterUpcoming,
            selected: filter == TripListFilter.upcoming,
            onTap: () => onFilterChanged(TripListFilter.upcoming),
          ),
          SizedBox(width: space.x2),
          _FilterPill(
            label: labels.filterPast,
            selected: filter == TripListFilter.past,
            onTap: () => onFilterChanged(TripListFilter.past),
          ),
          if (showDraftsFilter) ...[
            SizedBox(width: space.x2),
            _FilterPill(
              label: labels.filterDrafts,
              selected: filter == TripListFilter.drafts,
              onTap: () => onFilterChanged(TripListFilter.drafts),
            ),
          ],
        ],
      ),
    );
  }
}

class _FlatCompactList extends StatelessWidget {
  const _FlatCompactList({
    required this.trips,
    required this.participantsLabel,
    required this.weatherLabels,
  });

  final List<TripSummary> trips;
  final String Function(int count) participantsLabel;
  final WeatherBadgeLabels weatherLabels;

  @override
  Widget build(BuildContext context) {
    final space = context.vamoSpace;
    return Column(
      children: [
        for (final trip in trips) ...[
          CompactTripCard(
            trip: trip,
            participantsLabel: participantsLabel,
            weatherLabels: weatherLabels,
          ),
          SizedBox(height: space.x2),
        ],
      ],
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({
    required this.count,
    required this.labels,
    required this.onTap,
  });

  final int count;
  final TripsListScreenLabels labels;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final shape = context.vamoShape;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.08),
        borderRadius: shape.cardBorderRadius,
      ),
      child: ListTile(
        leading: Icon(
          Icons.cloud_upload_outlined,
          color: colors.secondary,
        ),
        title: Text(labels.syncPendingLabel(count)),
        subtitle: Text(labels.syncSubtitle),
        onTap: onTap,
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _NotificationsBell extends ConsumerWidget {
  const _NotificationsBell({required this.labels});

  final TripsListScreenLabels labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final unread = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;
    final badgeLabel = unread > 0
        ? (unread > 9 ? '9+' : '$unread')
        : null;

    return Semantics(
      button: true,
      label: badgeLabel == null
          ? labels.notificationsTooltip
          : '${labels.notificationsTooltip}, ${labels.notificationsUnreadBadge(unread)}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          VamoCircleIcon(
            diameter: 40,
            backgroundColor: colors.surface,
            shadow: false,
            onTap: () => context.push(AppRoutes.notifications),
            tooltip: labels.notificationsTooltip,
            child: Icon(
              Icons.notifications_outlined,
              color: colors.secondary,
              size: 22,
            ),
          ),
          if (badgeLabel != null)
            PositionedDirectional(
              top: -2,
              end: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.surface, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  badgeLabel,
                  style: type.labelSmall.copyWith(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
