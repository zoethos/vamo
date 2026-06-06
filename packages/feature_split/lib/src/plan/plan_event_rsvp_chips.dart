import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_rsvp_models.dart';
import 'plan_labels.dart';
import 'plan_repository.dart';

/// Going / Maybe / Declined controls for an activity plan item.
class PlanEventRsvpChips extends ConsumerStatefulWidget {
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
  ConsumerState<PlanEventRsvpChips> createState() => _PlanEventRsvpChipsState();
}

class _PlanEventRsvpChipsState extends ConsumerState<PlanEventRsvpChips> {
  EventRsvpStatus? _busyStatus;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final status in EventRsvpStatus.values)
          ChoiceChip(
            label: Text(_statusLabel(status)),
            selected: widget.myStatus == status,
            onSelected: widget.readOnly || _busyStatus != null
                ? null
                : (_) => _updateRsvp(status),
          ),
      ],
    );
  }

  Future<void> _updateRsvp(EventRsvpStatus status) async {
    setState(() => _busyStatus = status);
    try {
      final repo = ref.read(planRepositoryProvider);
      if (widget.myStatus == status) {
        await repo.clearEventRsvp(planItemId: widget.planItemId);
      } else {
        await repo.setEventRsvp(
          planItemId: widget.planItemId,
          status: status,
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.labels.eventRsvpUpdateFailed)),
      );
    } finally {
      if (mounted) {
        setState(() => _busyStatus = null);
      }
    }
  }

  String _statusLabel(EventRsvpStatus status) => switch (status) {
        EventRsvpStatus.going => widget.labels.rsvpGoing,
        EventRsvpStatus.maybe => widget.labels.rsvpMaybe,
        EventRsvpStatus.declined => widget.labels.rsvpDeclined,
      };
}
