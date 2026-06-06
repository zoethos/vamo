import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_rsvp_models.dart';
import 'plan_labels.dart';
import 'plan_repository.dart';

/// Going / Maybe / Declined controls for an activity plan item.
class PlanEventRsvpChips extends ConsumerWidget {
  const PlanEventRsvpChips({
    super.key,
    required this.planItemId,
    required this.labels,
    required this.myStatus,
    required this.readOnly,
  });

  final String planItemId;
  final PlanTabLabels labels;
  final EventRsvpStatus? myStatus;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      children: [
        for (final status in EventRsvpStatus.values)
          ChoiceChip(
            label: Text(_statusLabel(status)),
            selected: myStatus == status,
            onSelected: readOnly
                ? null
                : (_) {
                    if (myStatus == status) {
                      ref
                          .read(planRepositoryProvider)
                          .clearEventRsvp(planItemId: planItemId);
                    } else {
                      ref.read(planRepositoryProvider).setEventRsvp(
                            planItemId: planItemId,
                            status: status,
                          );
                    }
                  },
          ),
      ],
    );
  }

  String _statusLabel(EventRsvpStatus status) => switch (status) {
        EventRsvpStatus.going => labels.rsvpGoing,
        EventRsvpStatus.maybe => labels.rsvpMaybe,
        EventRsvpStatus.declined => labels.rsvpDeclined,
      };
}
