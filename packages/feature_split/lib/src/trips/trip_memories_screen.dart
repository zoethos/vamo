import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capture/capture_action_sheet.dart';
import '../capture/capture_tab.dart';
import '../sync/trip_realtime_binding.dart';
import 'trip_section_back_button.dart';
import 'trip_home_labels.dart';
import 'trips_providers.dart';

/// Trip memories gallery — photos + notes saved via capture (S43).
class TripMemoriesScreen extends ConsumerWidget {
  const TripMemoriesScreen({
    super.key,
    required this.tripId,
    required this.tripHomeLabels,
  });

  final String tripId;
  final TripHomeLabels tripHomeLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(tripRealtimeBindingProvider(tripId));

    final trip = ref.watch(tripDetailProvider(tripId));

    return trip.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(
          leading: TripSectionBackButton(tripId: tripId),
        ),
        body: AppErrorState(
          screen: 'trip_memories',
          message: tripHomeLabels.loadError,
          onRetry: () => ref.invalidate(tripDetailProvider(tripId)),
        ),
      ),
      data: (detail) {
        if (detail == null) {
          return Scaffold(
            appBar: AppBar(
              leading: TripSectionBackButton(tripId: tripId),
            ),
            body: AppEmptyState(
              screen: 'trip_memories',
              icon: Icons.auto_stories_outlined,
              title: tripHomeLabels.notFoundTitle,
              subtitle: tripHomeLabels.notFoundSubtitle,
            ),
          );
        }

        final readOnly = isTripReadOnly(TripLifecycle.parse(detail.lifecycle));

        return Scaffold(
          appBar: AppBar(
            leading: TripSectionBackButton(tripId: tripId),
            title: Text(tripHomeLabels.memoriesTitle),
            actions: [
              if (!readOnly)
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: tripHomeLabels.tabCapture,
                  onPressed: () => showCaptureActionSheet(
                    context: context,
                    tripId: tripId,
                  ),
                ),
            ],
          ),
          body: CaptureTab(
            tripId: tripId,
            showInlineAddActions: false,
          ),
        );
      },
    );
  }
}
