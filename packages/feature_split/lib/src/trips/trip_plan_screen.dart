import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../plan/plan_labels.dart';
import '../plan/plan_tab.dart';
import '../sync/trip_realtime_binding.dart';
import 'trip_home_labels.dart';
import 'trip_section_back_button.dart';
import 'trips_providers.dart';

class TripPlanScreen extends ConsumerStatefulWidget {
  const TripPlanScreen({
    super.key,
    required this.tripId,
    required this.tripHomeLabels,
    required this.planLabels,
  });

  final String tripId;
  final TripHomeLabels tripHomeLabels;
  final PlanTabLabels planLabels;

  @override
  ConsumerState<TripPlanScreen> createState() => _TripPlanScreenState();
}

class _TripPlanScreenState extends ConsumerState<TripPlanScreen> {
  final _planTabKey = GlobalKey<PlanTabState>();

  @override
  Widget build(BuildContext context) {
    ref.watch(tripRealtimeBindingProvider(widget.tripId));
    final trip = ref.watch(tripDetailProvider(widget.tripId));

    return trip.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => Scaffold(
        appBar: AppBar(leading: TripSectionBackButton(tripId: widget.tripId)),
        body: AppErrorState(
          screen: 'trip_plan',
          message: widget.tripHomeLabels.loadError,
          onRetry: () => ref.invalidate(tripDetailProvider(widget.tripId)),
        ),
      ),
      data: (detail) {
        if (detail == null) {
          return Scaffold(
            appBar: AppBar(
              leading: TripSectionBackButton(tripId: widget.tripId),
            ),
            body: AppEmptyState(
              screen: 'trip_plan',
              icon: Icons.map_outlined,
              title: widget.tripHomeLabels.notFoundTitle,
              subtitle: widget.tripHomeLabels.notFoundSubtitle,
            ),
          );
        }

        final readOnly = isTripReadOnly(TripLifecycle.parse(detail.lifecycle));

        return Scaffold(
          appBar: AppBar(
            leading: TripSectionBackButton(tripId: widget.tripId),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.planLabels.tabTitle),
                Text(
                  detail.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.vamoColors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
          body: PlanTab(
            key: _planTabKey,
            tripId: widget.tripId,
            labels: widget.planLabels,
            readOnly: readOnly,
            tripStartDateIso: detail.startDate,
            tripEndDateIso: detail.endDate,
            tripDestination: detail.destination,
            showBottomAddAction: true,
          ),
        );
      },
    );
  }
}
