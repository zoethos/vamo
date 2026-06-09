import 'package:app_core/app_core.dart';
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
    final disabled = widget.readOnly || _busyStatus != null;
    final selected =
        widget.myStatus == null ? <EventRsvpStatus>{} : {widget.myStatus!};

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<EventRsvpStatus>(
        segments: [
          ButtonSegment(
            value: EventRsvpStatus.going,
            label: _SegmentLabel(widget.labels.rsvpGoing),
            icon: _busyStatus == EventRsvpStatus.going
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline, size: 18),
          ),
          ButtonSegment(
            value: EventRsvpStatus.maybe,
            label: _SegmentLabel(widget.labels.rsvpMaybe),
            icon: _busyStatus == EventRsvpStatus.maybe
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.help_outline, size: 18),
          ),
          ButtonSegment(
            value: EventRsvpStatus.declined,
            label: _SegmentLabel(widget.labels.rsvpDeclined),
            icon: _busyStatus == EventRsvpStatus.declined
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cancel_outlined, size: 18),
          ),
        ],
        selected: selected,
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        onSelectionChanged: disabled
            ? null
            : (next) {
                if (next.isEmpty) {
                  if (widget.myStatus != null) {
                    _clearRsvp();
                  }
                  return;
                }
                _updateRsvp(next.first);
              },
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (!states.contains(WidgetState.selected)) {
              return AppColors.mistGray;
            }
            final value = selected.isEmpty ? null : selected.first;
            if (value == EventRsvpStatus.declined) {
              return AppColors.coralText.withValues(alpha: 0.14);
            }
            return AppColors.jadeTeal.withValues(alpha: 0.28);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (!states.contains(WidgetState.selected)) {
              return AppColors.graphite;
            }
            final value = selected.isEmpty ? null : selected.first;
            if (value == EventRsvpStatus.declined) {
              return AppColors.coralText;
            }
            return AppColors.ink;
          }),
        ),
      ),
    );
  }

  Future<void> _clearRsvp() async {
    setState(() => _busyStatus = widget.myStatus);
    try {
      await ref
          .read(planRepositoryProvider)
          .clearEventRsvp(planItemId: widget.planItemId);
    } catch (error, stackTrace) {
      if (!mounted) return;
      reportAndLog(
        error,
        stackTrace,
        screen: 'plan',
        action: 'clear_event_rsvp',
        analytics: ref.read(analyticsProvider),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.labels.eventRsvpUpdateFailed)),
      );
    } finally {
      if (mounted) {
        setState(() => _busyStatus = null);
      }
    }
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
    } catch (error, stackTrace) {
      if (!mounted) return;
      reportAndLog(
        error,
        stackTrace,
        screen: 'plan',
        action: 'update_event_rsvp',
        analytics: ref.read(analyticsProvider),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.labels.eventRsvpUpdateFailed)),
      );
    } finally {
      if (mounted) {
        setState(() => _busyStatus = null);
      }
    }
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.visible,
      softWrap: false,
    );
  }
}
