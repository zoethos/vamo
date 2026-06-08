import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../invites/invite_labels.dart';
import '../sync/trip_realtime_binding.dart';
import 'members_tab.dart';
import 'trip_section_back_button.dart';
import 'trip_home_labels.dart';
import 'trips_providers.dart';

class TripMembersScreen extends ConsumerStatefulWidget {
  const TripMembersScreen({
    super.key,
    required this.tripId,
    required this.tripHomeLabels,
    required this.inviteLabels,
  });

  final String tripId;
  final TripHomeLabels tripHomeLabels;
  final InviteLabels inviteLabels;

  @override
  ConsumerState<TripMembersScreen> createState() => _TripMembersScreenState();
}

class _TripMembersScreenState extends ConsumerState<TripMembersScreen> {
  final _membersTabKey = GlobalKey<MembersTabState>();

  @override
  Widget build(BuildContext context) {
    ref.watch(tripRealtimeBindingProvider(widget.tripId));

    final trip = ref.watch(tripDetailProvider(widget.tripId));

    return trip.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(
          leading: TripSectionBackButton(tripId: widget.tripId),
        ),
        body: AppErrorState(
          screen: 'trip_members',
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
              screen: 'trip_members',
              icon: Icons.map_outlined,
              title: widget.tripHomeLabels.notFoundTitle,
              subtitle: widget.tripHomeLabels.notFoundSubtitle,
            ),
          );
        }

        final readOnly =
            isTripReadOnly(TripLifecycle.parse(detail.lifecycle));

        return Scaffold(
          appBar: AppBar(
            leading: TripSectionBackButton(tripId: widget.tripId),
            title: Text(widget.tripHomeLabels.tabMembers),
            actions: [
              if (!readOnly)
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: widget.inviteLabels.inviteAction,
                  onPressed: () =>
                      _membersTabKey.currentState?.openInviteFlow(),
                ),
            ],
          ),
          body: MembersTab(
            key: _membersTabKey,
            tripId: widget.tripId,
            inviteLabels: widget.inviteLabels,
          ),
        );
      },
    );
  }
}
