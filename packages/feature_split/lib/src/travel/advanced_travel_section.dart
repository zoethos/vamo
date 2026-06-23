import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../plan/plan_models.dart';
import 'advanced_travel_labels.dart';
import 'travel_leg.dart';

/// Ordered travel-leg editor shown on New Trip when "Plan how you'll travel"
/// is on. Pure local state — captures the constraint envelope (mode · window ·
/// reach) that the AI route-drafter will later solve. No AI/server here.
class AdvancedTravelSection extends StatelessWidget {
  const AdvancedTravelSection({
    super.key,
    required this.labels,
    required this.legs,
    required this.onChanged,
    required this.unit,
    required this.datePickerLabels,
    this.tripStart,
    this.tripEnd,
  });

  final AdvancedTravelLabels labels;
  final List<TravelLeg> legs;
  final ValueChanged<List<TravelLeg>> onChanged;
  final DistanceUnit unit;
  final VamoDatePickerLabels datePickerLabels;
  final DateTime? tripStart;
  final DateTime? tripEnd;

  Future<void> _editLeg(BuildContext context, {int? index}) async {
    final existing = index == null ? null : legs[index];
    final result = await showTravelLegEditor(
      context: context,
      labels: labels,
      unit: unit,
      datePickerLabels: datePickerLabels,
      tripStart: tripStart,
      tripEnd: tripEnd,
      initial: existing,
      canRemove: index != null,
    );
    if (result == null) return;
    final next = [...legs];
    if (result.removed) {
      if (index != null) next.removeAt(index);
    } else if (index == null) {
      next.add(result.leg!);
    } else {
      next[index] = result.leg!;
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                labels.legsSectionTitle.toUpperCase(),
                style: textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceMuted,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            Text(
              labels.legsInOrder,
              style:
                  textTheme.bodySmall?.copyWith(color: colors.onSurfaceMuted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (legs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              labels.noLegs,
              style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
            ),
          )
        else
          for (var i = 0; i < legs.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _LegTile(
                leg: legs[i],
                labels: labels,
                unit: unit,
                onTap: () => _editLeg(context, index: i),
              ),
            ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => _editLeg(context),
            icon: const Icon(Icons.add, size: 18),
            label: Text(labels.addLeg),
          ),
        ),
      ],
    );
  }
}

/// Maps a travel mode to its Plan type accent (train=jade, flight=sky,
/// road=transfer orange) so legs read in the same colour language as the Plan.
Color travelModeColor(TravelMode mode) => switch (mode.planKind) {
      PlanItemKind.train => VamoPlanTypeColors.train,
      PlanItemKind.flight => VamoPlanTypeColors.flight,
      _ => VamoPlanTypeColors.transfer,
    };

String legWindowSummary(TravelLeg leg, String anyTime) {
  final start = leg.windowStart;
  final end = leg.windowEnd;
  if (start == null && end == null) return anyTime;
  final fmt = DateFormat('MMM d');
  if (start != null && end != null) {
    return '${fmt.format(start)} – ${fmt.format(end)}';
  }
  return fmt.format((start ?? end)!);
}

String legReachSummary(
  TravelLeg leg,
  DistanceUnit unit,
  AdvancedTravelLabels labels,
) {
  final reach = leg.reach;
  if (reach.isUnlimited) return labels.reachNoLimit;
  if (reach.type == ReachType.distance) {
    final value = unit.fromKm(reach.value!);
    return '≤ ${_trimNum(value)} ${unit.name}';
  }
  return '≤ ${_trimNum(reach.value!)} ${labels.reachHoursUnit}';
}

String _trimNum(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class _LegTile extends StatelessWidget {
  const _LegTile({
    required this.leg,
    required this.labels,
    required this.unit,
    required this.onTap,
  });

  final TravelLeg leg;
  final AdvancedTravelLabels labels;
  final DistanceUnit unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final color = travelModeColor(leg.mode);
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(leg.mode.icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      labels.modeLabel(leg.mode),
                      style: textTheme.titleMedium?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${legWindowSummary(leg, labels.windowAnyTime)} · '
                      '${legReachSummary(leg, unit, labels)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.onSurfaceMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Result of the leg editor sheet: either an upserted [leg] or a [removed] flag.
class TravelLegEditResult {
  const TravelLegEditResult.saved(TravelLeg this.leg) : removed = false;
  const TravelLegEditResult.removed()
      : leg = null,
        removed = true;

  final TravelLeg? leg;
  final bool removed;
}

Future<TravelLegEditResult?> showTravelLegEditor({
  required BuildContext context,
  required AdvancedTravelLabels labels,
  required DistanceUnit unit,
  required VamoDatePickerLabels datePickerLabels,
  TravelLeg? initial,
  DateTime? tripStart,
  DateTime? tripEnd,
  bool canRemove = false,
}) {
  return showModalBottomSheet<TravelLegEditResult>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetContext) => _TravelLegEditor(
      labels: labels,
      unit: unit,
      datePickerLabels: datePickerLabels,
      initial: initial,
      tripStart: tripStart,
      tripEnd: tripEnd,
      canRemove: canRemove,
    ),
  );
}

class _TravelLegEditor extends StatefulWidget {
  const _TravelLegEditor({
    required this.labels,
    required this.unit,
    required this.datePickerLabels,
    required this.initial,
    required this.tripStart,
    required this.tripEnd,
    required this.canRemove,
  });

  final AdvancedTravelLabels labels;
  final DistanceUnit unit;
  final VamoDatePickerLabels datePickerLabels;
  final TravelLeg? initial;
  final DateTime? tripStart;
  final DateTime? tripEnd;
  final bool canRemove;

  @override
  State<_TravelLegEditor> createState() => _TravelLegEditorState();
}

class _TravelLegEditorState extends State<_TravelLegEditor> {
  late TravelMode _mode;
  DateTime? _windowStart;
  DateTime? _windowEnd;
  late ReachLimit _reach;
  late ReachType _reachType;

  // Canonical km presets; rendered in the user's unit.
  static const _distancePresetsKm = [100.0, 300.0, 600.0];
  static const _timePresetsHours = [2.0, 5.0, 8.0];

  @override
  void initState() {
    super.initState();
    final leg = widget.initial;
    _mode = leg?.mode ?? TravelMode.car;
    _windowStart = leg?.windowStart;
    _windowEnd = leg?.windowEnd;
    _reach = leg?.reach ?? const ReachLimit.none();
    _reachType = _reach.type;
  }

  Future<void> _pickWindow() async {
    final start = await showVamoDatePicker(
      context: context,
      labels: widget.datePickerLabels,
      initialDate: _windowStart ?? widget.tripStart,
      firstDate: widget.tripStart,
      lastDate: widget.tripEnd,
    );
    if (!mounted) return;
    if (start.outcome == VamoDatePickOutcome.skipped) {
      setState(() {
        _windowStart = null;
        _windowEnd = null;
      });
      return;
    }
    if (start.outcome != VamoDatePickOutcome.selected) return;
    setState(() => _windowStart = start.date);

    final end = await showVamoDatePicker(
      context: context,
      labels: widget.datePickerLabels,
      initialDate: _windowEnd ?? start.date,
      firstDate: start.date,
      lastDate: widget.tripEnd,
    );
    if (!mounted) return;
    switch (end.outcome) {
      case VamoDatePickOutcome.selected:
        setState(() => _windowEnd = end.date);
      case VamoDatePickOutcome.skipped:
        setState(() => _windowEnd = null);
      case VamoDatePickOutcome.cancelled:
        break;
    }
  }

  void _selectPreset(double value) {
    setState(() {
      _reach = _reachType == ReachType.distance
          ? ReachLimit.distanceKm(widget.unit.toKm(value))
          : ReachLimit.hoursPerDay(value);
    });
  }

  void _selectNoLimit() => setState(() => _reach = const ReachLimit.none());

  void _switchReachType(ReachType type) {
    setState(() {
      _reachType = type;
      _reach = const ReachLimit.none();
    });
  }

  String get _bigValue {
    if (_reach.isUnlimited) return widget.labels.reachNoLimit;
    if (_reach.type == ReachType.distance) {
      return _trimNum(widget.unit.fromKm(_reach.value!));
    }
    return _trimNum(_reach.value!);
  }

  String get _bigUnit {
    if (_reach.isUnlimited) return '';
    return _reach.type == ReachType.distance
        ? widget.unit.name
        : widget.labels.reachHoursUnit;
  }

  void _save() {
    Navigator.of(context).pop(
      TravelLegEditResult.saved(
        TravelLeg(
          mode: _mode,
          windowStart: _windowStart,
          windowEnd: _windowEnd,
          reach: _reach,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final l = widget.labels;
    final textTheme = Theme.of(context).textTheme;
    final presets = _reachType == ReachType.distance
        ? _distancePresetsKm.map((km) => widget.unit.fromKm(km)).toList()
        : _timePresetsHours;

    bool presetSelected(double value) {
      if (_reach.isUnlimited) return false;
      final current = _reach.type == ReachType.distance
          ? widget.unit.fromKm(_reach.value!)
          : _reach.value!;
      return (current - value).abs() < 0.5;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.legEditorTitle,
                    style: textTheme.titleLarge?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.canRemove)
                  TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop(const TravelLegEditResult.removed()),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.error,
                    ),
                    child: Text(l.removeLeg),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _SectionLabel(l.modeSectionTitle),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in TravelMode.values)
                  ChoiceChip(
                    avatar: Icon(
                      mode.icon,
                      size: 18,
                      color: _mode == mode
                          ? travelModeColor(mode)
                          : colors.onSurfaceMuted,
                    ),
                    label: Text(l.modeLabel(mode)),
                    selected: _mode == mode,
                    onSelected: (_) => setState(() => _mode = mode),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _SectionLabel(l.windowSectionTitle),
            OutlinedButton.icon(
              onPressed: _pickWindow,
              style: OutlinedButton.styleFrom(
                alignment: AlignmentDirectional.centerStart,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(
                legWindowSummary(
                  TravelLeg(
                    mode: _mode,
                    windowStart: _windowStart,
                    windowEnd: _windowEnd,
                  ),
                  l.windowAnyTime,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l.windowOptionalHint,
              style: textTheme.bodySmall?.copyWith(color: colors.success),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _SectionLabel(l.reachSectionTitle)),
                SegmentedButton<ReachType>(
                  segments: [
                    ButtonSegment(
                      value: ReachType.distance,
                      label: Text(l.reachDistance),
                    ),
                    ButtonSegment(
                      value: ReachType.time,
                      label: Text(l.reachTime),
                    ),
                  ],
                  selected: {_reachType},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _switchReachType(s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _bigValue,
                  style: textTheme.displaySmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (_bigUnit.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    _bigUnit,
                    style: textTheme.titleMedium
                        ?.copyWith(color: colors.onSurfaceMuted),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _reachType == ReachType.distance
                  ? l.reachDistanceCaption
                  : l.reachTimeCaption,
              style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceMuted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in presets)
                  ChoiceChip(
                    label: Text(
                      '${_trimNum(value)} '
                      '${_reachType == ReachType.distance ? widget.unit.name : l.reachHoursUnit}',
                    ),
                    selected: presetSelected(value),
                    onSelected: (_) => _selectPreset(value),
                  ),
                ChoiceChip(
                  label: Text(l.reachNoLimit),
                  selected: _reach.isUnlimited,
                  onSelected: (_) => _selectNoLimit(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              l.unitsFootnote,
              style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceMuted),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: colors.action,
                foregroundColor: colors.onAction,
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(l.saveLeg),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.vamoColors.onSurfaceMuted,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}
