import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_rsvp_models.dart';
import 'plan_labels.dart';
import 'plan_repository.dart';

/// Compact RSVP state pill for plan event cards (S43).
class PlanEventRsvpStateIcon extends StatelessWidget {
  const PlanEventRsvpStateIcon({
    super.key,
    required this.myStatus,
    required this.unsetLabel,
    this.busy = false,
  });

  final EventRsvpStatus? myStatus;
  final String unsetLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;

    if (busy) {
      return SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.secondary,
            ),
          ),
        ),
      );
    }

    if (myStatus == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.border.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          child: Text(
            unsetLabel,
            style: type.labelSmall.copyWith(
              color: colors.onSurfaceMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    final (icon, color, background) = switch (myStatus!) {
      EventRsvpStatus.going => (
          Icons.check_rounded,
          colors.success,
          colors.success.withValues(alpha: 0.16),
        ),
      EventRsvpStatus.maybe => (
          Icons.help_outline_rounded,
          colors.warning,
          colors.warning.withValues(alpha: 0.18),
        ),
      EventRsvpStatus.declined => (
          Icons.close_rounded,
          colors.error,
          colors.error.withValues(alpha: 0.14),
        ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

/// Tappable RSVP control — opens [showPlanEventRsvpPicker] on tap.
class PlanEventRsvpControl extends ConsumerStatefulWidget {
  const PlanEventRsvpControl({
    super.key,
    required this.planItemId,
    required this.labels,
    required this.myStatus,
  });

  final String planItemId;
  final PlanTabLabels labels;
  final EventRsvpStatus? myStatus;

  @override
  ConsumerState<PlanEventRsvpControl> createState() =>
      _PlanEventRsvpControlState();
}

class _PlanEventRsvpControlState extends ConsumerState<PlanEventRsvpControl> {
  bool _busy = false;

  Future<void> _openPicker() async {
    if (_busy) return;
    await showPlanEventRsvpPicker(
      context: context,
      ref: ref,
      planItemId: widget.planItemId,
      labels: widget.labels,
      myStatus: widget.myStatus,
      onBusyChanged: (busy) {
        if (mounted) setState(() => _busy = busy);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.myStatus == null
          ? widget.labels.eventRsvpSection
          : switch (widget.myStatus!) {
              EventRsvpStatus.going => widget.labels.rsvpGoing,
              EventRsvpStatus.maybe => widget.labels.rsvpMaybe,
              EventRsvpStatus.declined => widget.labels.rsvpDeclined,
            },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _busy ? null : _openPicker,
          borderRadius: BorderRadius.circular(999),
          child: PlanEventRsvpStateIcon(
            myStatus: widget.myStatus,
            unsetLabel: widget.labels.eventRsvpSection,
            busy: _busy,
          ),
        ),
      ),
    );
  }
}

Future<void> showPlanEventRsvpPicker({
  required BuildContext context,
  required WidgetRef ref,
  required String planItemId,
  required PlanTabLabels labels,
  required EventRsvpStatus? myStatus,
  void Function(bool busy)? onBusyChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _PlanEventRsvpPickerSheet(
      planItemId: planItemId,
      labels: labels,
      myStatus: myStatus,
      onBusyChanged: onBusyChanged,
    ),
  );
}

class _PlanEventRsvpPickerSheet extends ConsumerStatefulWidget {
  const _PlanEventRsvpPickerSheet({
    required this.planItemId,
    required this.labels,
    required this.myStatus,
    this.onBusyChanged,
  });

  final String planItemId;
  final PlanTabLabels labels;
  final EventRsvpStatus? myStatus;
  final void Function(bool busy)? onBusyChanged;

  @override
  ConsumerState<_PlanEventRsvpPickerSheet> createState() =>
      _PlanEventRsvpPickerSheetState();
}

class _PlanEventRsvpPickerSheetState
    extends ConsumerState<_PlanEventRsvpPickerSheet> {
  EventRsvpStatus? _busyStatus;

  Future<void> _select(EventRsvpStatus status) async {
    setState(() => _busyStatus = status);
    widget.onBusyChanged?.call(true);
    try {
      if (widget.myStatus == status) {
        await ref
            .read(planRepositoryProvider)
            .clearEventRsvp(planItemId: widget.planItemId);
      } else {
        await ref.read(planRepositoryProvider).setEventRsvp(
              planItemId: widget.planItemId,
              status: status,
            );
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error, stackTrace) {
      if (!mounted) return;
      reportAndLog(
        error,
        stackTrace,
        screen: 'plan',
        action: 'pick_event_rsvp',
        analytics: ref.read(analyticsProvider),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.labels.eventRsvpUpdateFailed)),
      );
    } finally {
      widget.onBusyChanged?.call(false);
      if (mounted) {
        setState(() => _busyStatus = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;

    Widget option({
      required EventRsvpStatus status,
      required IconData icon,
      required Color iconColor,
      required String label,
    }) {
      final selected = widget.myStatus == status;
      final busy = _busyStatus == status;
      return ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(label, style: type.bodyLarge),
        trailing: busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.secondary,
                ),
              )
            : selected
                ? Icon(Icons.check, color: colors.secondary)
                : null,
        onTap: _busyStatus != null ? null : () => _select(status),
      );
    }

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(space.x4, 0, space.x4, space.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.labels.eventRsvpSection,
            style: type.titleSmall.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: space.x1),
          option(
            status: EventRsvpStatus.going,
            icon: Icons.check_circle_outline,
            iconColor: colors.success,
            label: widget.labels.rsvpGoing,
          ),
          option(
            status: EventRsvpStatus.maybe,
            icon: Icons.help_outline,
            iconColor: colors.warning,
            label: widget.labels.rsvpMaybe,
          ),
          option(
            status: EventRsvpStatus.declined,
            icon: Icons.cancel_outlined,
            iconColor: colors.error,
            label: widget.labels.rsvpDeclined,
          ),
        ],
      ),
    );
  }
}
