import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'advanced_travel_labels.dart';
import 'travel_leg.dart';

/// Advanced Travel captures the constraint envelope (mode · window · reach)
/// that AI route drafting can solve later. Widgets here keep UI state thin; the
/// reusable rules live in [TravelLeg], summaries, and route serialization.
class AdvancedTravelSection extends StatelessWidget {
  const AdvancedTravelSection({
    super.key,
    required this.labels,
    required this.modes,
    required this.onModesChanged,
    required this.legs,
    required this.onChanged,
    required this.unit,
    this.tripStart,
    this.tripEnd,
  });

  final AdvancedTravelLabels labels;
  final Set<TravelMode> modes;
  final ValueChanged<Set<TravelMode>> onModesChanged;
  final List<TravelLeg> legs;
  final ValueChanged<List<TravelLeg>> onChanged;
  final DistanceUnit unit;
  final DateTime? tripStart;
  final DateTime? tripEnd;

  Future<void> _editLeg(BuildContext context, {int? index}) async {
    final existing = index == null ? null : legs[index];
    final result = await showTravelLegEditor(
      context: context,
      labels: labels,
      unit: unit,
      initial: existing,
      tripStart: tripStart,
      tripEnd: tripEnd,
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

  void _toggleMode(TravelMode mode) {
    final next = {...modes};
    if (!next.add(mode)) next.remove(mode);
    onModesChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel("MODES YOU'LL USE"),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in TravelMode.values)
                _ModeChip(
                  label: labels.modeLabel(mode),
                  icon: mode.icon,
                  color: travelModeColor(mode),
                  selected: modes.contains(mode),
                  unselectedTextColor: VamoTravelTokens.mute2,
                  onTap: () => _toggleMode(mode),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _SectionLabel(labels.legsSectionTitle)),
              Text(
                labels.legsInOrder,
                style: const TextStyle(
                  color: VamoTravelTokens.mute2,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < legs.length; i++) ...[
            _LegRow(
              leg: legs[i],
              labels: labels,
              unit: unit,
              onTap: () => _editLeg(context, index: i),
            ),
            const SizedBox(height: 9),
          ],
          _AddLegRow(
            label: _addLegLabel(labels),
            onTap: () => _editLeg(context),
          ),
          const SizedBox(height: 14),
          _FeasibilityBanner(
            legs: legs,
            tripStart: tripStart,
            tripEnd: tripEnd,
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

Color travelModeColor(TravelMode mode) => switch (mode) {
      TravelMode.car => VamoTravelTokens.carOrange,
      TravelMode.motorbike => VamoTravelTokens.coral,
      TravelMode.bike => VamoTravelTokens.jade,
      TravelMode.train => VamoTravelTokens.jadeBright,
      TravelMode.flight => VamoTravelTokens.sky,
      TravelMode.bus => VamoTravelTokens.plum,
    };

String legWindowSummary(TravelLeg leg, String anyTime) {
  final start = leg.windowStart;
  final end = leg.windowEnd;
  if (start == null && end == null) return anyTime;
  final fmt = DateFormat('MMM d');
  if (start != null && end != null) {
    final sameMonth = start.month == end.month && start.year == end.year;
    final range = sameMonth
        ? '${fmt.format(start)} – ${end.day}'
        : '${fmt.format(start)} – ${fmt.format(end)}';
    return range;
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
    return '≤ ${_trimDistance(value, unit)} ${distanceUnitLabel(unit)}';
  }
  return '≤ ${_trimNum(reach.value!)}${labels.reachHoursUnit}';
}

String distanceUnitLabel(DistanceUnit unit) =>
    unit == DistanceUnit.km ? 'km' : 'mi';

String _trimNum(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _trimDistance(double value, DistanceUnit unit) =>
    unit == DistanceUnit.km ? _trimNum(value) : value.round().toString();

String _addLegLabel(AdvancedTravelLabels labels) =>
    labels.addLeg == 'Add leg' ? 'Add a travel leg' : labels.addLeg;

String _modeCaption(AdvancedTravelLabels labels, TravelMode mode) =>
    labels.modeLabel(mode).toLowerCase();

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.unselectedTextColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final Color unselectedTextColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? VamoTravelTokens.tint(color)
              : VamoTravelTokens.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color : VamoTravelTokens.border,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: selected ? color : unselectedTextColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color:
                    selected ? VamoTravelTokens.inkSoft : unselectedTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegRow extends StatelessWidget {
  const _LegRow({
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
    final color = travelModeColor(leg.mode);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: VamoTravelTokens.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: VamoTravelTokens.hairline),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A0C0E16),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: VamoTravelTokens.tint(color),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(leg.mode.icon, size: 20, color: color),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    labels.modeLabel(leg.mode),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VamoTravelTokens.ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${legWindowSummary(leg, labels.windowAnyTime)} · '
                    '${legReachSummary(leg, unit, labels)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VamoTravelTokens.mute,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 11),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: VamoTravelTokens.chevron,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddLegRow extends StatelessWidget {
  const _AddLegRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: VamoTravelTokens.borderDash,
          radius: 13,
          strokeWidth: 1.5,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              const Icon(Icons.add, size: 19, color: VamoTravelTokens.plum),
              const SizedBox(width: 9),
              Text(
                label,
                style: const TextStyle(
                  color: VamoTravelTokens.plum,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeasibilityBanner extends StatelessWidget {
  const _FeasibilityBanner({
    required this.legs,
    required this.tripStart,
    required this.tripEnd,
  });

  final List<TravelLeg> legs;
  final DateTime? tripStart;
  final DateTime? tripEnd;

  @override
  Widget build(BuildContext context) {
    final tripRange = _tripRangeLabel(tripStart, tripEnd);
    final count = legs.length == 1 ? '1 leg' : '${legs.length} legs';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: VamoTravelTokens.feasGreenBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VamoTravelTokens.feasGreenBd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified,
            color: VamoTravelTokens.feasGreenFg,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              legs.isEmpty
                  ? 'Feasible — AI can solve inside your selected travel envelope.'
                  : 'Feasible — AI can connect 8 stops across your $count within the $tripRange range.',
              style: const TextStyle(
                color: VamoTravelTokens.inkSoft,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _tripRangeLabel(DateTime? start, DateTime? end) {
    if (start == null && end == null) return 'trip';
    final leg =
        TravelLeg(mode: TravelMode.car, windowStart: start, windowEnd: end);
    return legWindowSummary(leg, 'trip');
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: VamoTravelTokens.slate,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
  }
}

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
  TravelLeg? initial,
  DateTime? tripStart,
  DateTime? tripEnd,
  bool canRemove = false,
}) {
  return Navigator.of(context).push<TravelLegEditResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _TravelLegEditor(
        labels: labels,
        unit: unit,
        initial: initial,
        tripStart: tripStart,
        tripEnd: tripEnd,
        canRemove: canRemove,
      ),
    ),
  );
}

class _TravelLegEditor extends StatefulWidget {
  const _TravelLegEditor({
    required this.labels,
    required this.unit,
    required this.initial,
    required this.tripStart,
    required this.tripEnd,
    required this.canRemove,
  });

  final AdvancedTravelLabels labels;
  final DistanceUnit unit;
  final TravelLeg? initial;
  final DateTime? tripStart;
  final DateTime? tripEnd;
  final bool canRemove;

  @override
  State<_TravelLegEditor> createState() => _TravelLegEditorState();
}

class _TravelLegEditorState extends State<_TravelLegEditor> {
  static const _distancePresetsKm = [100.0, 300.0, 600.0];
  static const _timePresetsHours = [2.0, 4.0, 5.0, 8.0];

  late TravelMode _mode;
  DateTime? _windowStart;
  DateTime? _windowEnd;
  String? _windowStartTime;
  String? _windowEndTime;
  late ReachLimit _reach;
  late ReachType _reachType;

  @override
  void initState() {
    super.initState();
    final leg = widget.initial;
    _mode = leg?.mode ?? TravelMode.car;
    _windowStart = leg?.windowStart ?? widget.tripStart;
    _windowEnd = leg?.windowEnd ?? widget.tripEnd ?? _windowStart;
    _windowStartTime = leg?.windowStartTime;
    _windowEndTime = leg?.windowEndTime;
    _reach = leg?.reach ?? const ReachLimit.distanceKm(600);
    _reachType = _reach.type;
  }

  Future<void> _pickWindow() async {
    final selected = await showVamoDateScroller(
      context: context,
      initialStart: _windowStart,
      initialEnd: _windowEnd,
      firstDate: widget.tripStart,
      lastDate: widget.tripEnd,
      allowTimes: true,
    );
    if (!mounted || selected == null) return;
    setState(() {
      _windowStart = selected.start;
      _windowEnd = selected.end;
      _windowStartTime = selected.startTime;
      _windowEndTime = selected.endTime;
    });
  }

  void _switchReachType(ReachType type) {
    setState(() {
      _reachType = type;
      _reach = type == ReachType.distance
          ? const ReachLimit.distanceKm(600)
          : const ReachLimit.hoursPerDay(5);
    });
  }

  void _selectDistance(double value, {required bool noLimit}) {
    setState(() {
      _reach = noLimit
          ? const ReachLimit.none()
          : ReachLimit.distanceKm(widget.unit.toKm(value));
      _reachType = ReachType.distance;
    });
  }

  void _selectTime(double value) {
    setState(() {
      _reach = ReachLimit.hoursPerDay(value);
      _reachType = ReachType.time;
    });
  }

  String get _bigValue {
    if (_reach.isUnlimited) return '∞';
    if (_reach.type == ReachType.distance) {
      return _trimNum(widget.unit.fromKm(_reach.value!));
    }
    return _trimNum(_reach.value!);
  }

  String get _bigSuffix {
    if (_reach.isUnlimited) return '';
    return _reach.type == ReachType.distance
        ? ' ${distanceUnitLabel(widget.unit)}'
        : widget.labels.reachHoursUnit;
  }

  String get _durationLabel {
    final start = _windowStart;
    final end = _windowEnd;
    if (start == null || end == null) return '';
    final days = DateTime(end.year, end.month, end.day)
            .difference(DateTime(start.year, start.month, start.day))
            .inDays +
        1;
    return days <= 1 ? '1 day' : '$days days';
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove travel leg?'),
        content:
            const Text('This leg will be removed from the route envelope.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.labels.removeLeg),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    Navigator.of(context).pop(const TravelLegEditResult.removed());
  }

  void _save() {
    Navigator.of(context).pop(
      TravelLegEditResult.saved(
        TravelLeg(
          mode: _mode,
          windowStart: _windowStart,
          windowEnd: _windowEnd,
          windowStartTime: _windowStartTime,
          windowEndTime: _windowEndTime,
          reach: _reach,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.labels;
    final windowText = legWindowSummary(
      TravelLeg(mode: _mode, windowStart: _windowStart, windowEnd: _windowEnd),
      l.windowAnyTime,
    );
    return Scaffold(
      backgroundColor: VamoTravelTokens.appBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 18, 6),
              child: Row(
                children: [
                  _IconTap(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      l.legEditorTitle,
                      style: const TextStyle(
                        color: VamoTravelTokens.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (widget.canRemove)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _remove,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: Text(
                          l.removeLeg,
                          style: const TextStyle(
                            color: VamoTravelTokens.destructive,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 116),
                physics: const BouncingScrollPhysics(),
                children: [
                  _SectionLabel(l.modeSectionTitle),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final mode in TravelMode.values)
                        _ModeChip(
                          label: l.modeLabel(mode),
                          icon: mode.icon,
                          color: travelModeColor(mode),
                          selected: _mode == mode,
                          unselectedTextColor: VamoTravelTokens.slate,
                          onTap: () => setState(() => _mode = mode),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SectionLabel(l.windowSectionTitle),
                  const SizedBox(height: 8),
                  _FieldRow(
                    onTap: _pickWindow,
                    leading: Icons.calendar_month,
                    leadingColor: VamoTravelTokens.coral,
                    value: windowText,
                    trailing: _durationLabel,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 17,
                        color: VamoTravelTokens.jade,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          l.windowOptionalHint,
                          style: const TextStyle(
                            color: VamoTravelTokens.slate,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: _SectionLabel(l.reachSectionTitle)),
                      _SegmentedReachControl(
                        selected: _reachType,
                        labels: l,
                        onChanged: _switchReachType,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ReachValueBlock(
                    value: _bigValue,
                    suffix: _bigSuffix,
                    caption: _reachType == ReachType.distance
                        ? "max you'll cover by ${_modeCaption(l, _mode)} on this leg"
                        : "max time you'll spend moving",
                  ),
                  const SizedBox(height: 7),
                  if (_reachType == ReachType.distance)
                    _PresetScroller(
                      children: [
                        for (final km in _distancePresetsKm)
                          _PresetChip(
                            label:
                                '${_trimDistance(widget.unit.fromKm(km), widget.unit)} ${distanceUnitLabel(widget.unit)}',
                            selected: !_reach.isUnlimited &&
                                _reach.type == ReachType.distance &&
                                (widget.unit.fromKm(_reach.value!) -
                                            widget.unit.fromKm(km))
                                        .abs() <
                                    0.5,
                            onTap: () => _selectDistance(
                              widget.unit.fromKm(km),
                              noLimit: false,
                            ),
                          ),
                        _PresetChip(
                          label: l.reachNoLimit,
                          selected: _reach.isUnlimited,
                          onTap: () => _selectDistance(9999, noLimit: true),
                        ),
                      ],
                    )
                  else
                    _PresetScroller(
                      children: [
                        for (final hours in _timePresetsHours)
                          _PresetChip(
                            label: '${_trimNum(hours)}h',
                            selected: !_reach.isUnlimited &&
                                _reach.type == ReachType.time &&
                                (_reach.value! - hours).abs() < 0.1,
                            onTap: () => _selectTime(hours),
                          ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'Units follow your profile · ${distanceUnitLabel(widget.unit)} · change in Profile › Preferences',
                    style: const TextStyle(
                      color: VamoTravelTokens.mute2,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 10, 18, 16),
        child: _PrimaryActionButton(
          label: l.saveLeg,
          onTap: _save,
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.onTap,
    required this.leading,
    required this.leadingColor,
    required this.value,
    required this.trailing,
  });

  final VoidCallback onTap;
  final IconData leading;
  final Color leadingColor;
  final String value;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: VamoTravelTokens.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: VamoTravelTokens.border, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(leading, size: 20, color: leadingColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: VamoTravelTokens.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (trailing.isNotEmpty)
              Text(
                trailing,
                style: const TextStyle(
                  color: VamoTravelTokens.mute2,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedReachControl extends StatelessWidget {
  const _SegmentedReachControl({
    required this.selected,
    required this.labels,
    required this.onChanged,
  });

  final ReachType selected;
  final AdvancedTravelLabels labels;
  final ValueChanged<ReachType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: VamoTravelTokens.segBg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            label: labels.reachDistance,
            selected: selected == ReachType.distance,
            onTap: () => onChanged(ReachType.distance),
          ),
          _Segment(
            label: labels.reachTime,
            selected: selected == ReachType.time,
            onTap: () => onChanged(ReachType.time),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? VamoTravelTokens.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : VamoTravelTokens.slate,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ReachValueBlock extends StatelessWidget {
  const _ReachValueBlock({
    required this.value,
    required this.suffix,
    required this.caption,
  });

  final String value;
  final String suffix;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Column(
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: VamoTravelTokens.ink,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                if (suffix.isNotEmpty)
                  TextSpan(
                    text: suffix,
                    style: const TextStyle(
                      color: VamoTravelTokens.mute,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: VamoTravelTokens.mute2,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetScroller extends StatelessWidget {
  const _PresetScroller({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 39,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) => children[index],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? VamoTravelTokens.ink : VamoTravelTokens.chipBg,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : VamoTravelTokens.inkSoft,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(icon, size: 24, color: VamoTravelTokens.ink),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: VamoTravelTokens.lime,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: VamoTravelTokens.lime.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: VamoTravelTokens.ink,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + 7;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 5;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth;
}
