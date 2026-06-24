import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'vamo_travel_tokens.dart';

@immutable
class VamoDateScrollerValue {
  const VamoDateScrollerValue({
    required this.start,
    required this.end,
    this.startTime,
    this.endTime,
  });

  final DateTime start;
  final DateTime end;
  final String? startTime;
  final String? endTime;

  bool get isSingle => _sameDate(start, end);
  int get durationDays => _dayIndex(end) - _dayIndex(start) + 1;
}

Future<VamoDateScrollerValue?> showVamoDateScroller({
  required BuildContext context,
  DateTime? initialStart,
  DateTime? initialEnd,
  DateTime? firstDate,
  DateTime? lastDate,
  bool allowTimes = true,
}) {
  return showModalBottomSheet<VamoDateScrollerValue>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.24),
    builder: (context) {
      return _DateScrollerSheet(
        initialStart: initialStart,
        initialEnd: initialEnd,
        firstDate: firstDate,
        lastDate: lastDate,
        allowTimes: allowTimes,
      );
    },
  );
}

class _DateScrollerSheet extends StatefulWidget {
  const _DateScrollerSheet({
    required this.initialStart,
    required this.initialEnd,
    required this.firstDate,
    required this.lastDate,
    required this.allowTimes,
  });

  final DateTime? initialStart;
  final DateTime? initialEnd;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool allowTimes;

  @override
  State<_DateScrollerSheet> createState() => _DateScrollerSheetState();
}

class _DateScrollerSheetState extends State<_DateScrollerSheet> {
  static const _times = [
    '07:00',
    '08:00',
    '09:00',
    '10:00',
    '12:00',
    '14:00',
    '16:00',
    '18:00',
    '20:00',
  ];

  late final DateTime _firstDate;
  late final DateTime _lastDate;
  late DateTime _start;
  late DateTime _end;
  String? _activePreset;
  bool _timesEnabled = false;
  String _startTime = '09:00';
  String _endTime = '18:00';

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    final seededStart =
        _dateOnly(widget.initialStart ?? widget.firstDate ?? today);
    _firstDate = _dateOnly(widget.firstDate ?? seededStart);
    _lastDate = _dateOnly(widget.lastDate ?? _addMonths(_firstDate, 6));
    _start = _clampDate(seededStart);
    _end = _clampDate(_dateOnly(widget.initialEnd ?? _start));
    if (_end.isBefore(_start)) _end = _start;
  }

  void _tapDay(DateTime day) {
    final picked = _dateOnly(day);
    setState(() {
      _activePreset = null;
      // Behavior summary:
      // 1. First tap = single-day trip (start = end); CTA reads "Use May 12".
      // 2. Second tap extends to a range; tapping earlier than start flips them;
      //    a third tap starts over.
      // 3. Times are opt-in -- end date alone suffices for most trips; times
      //    stay collapsed until asked for.
      // 4. Scroll, don't paginate -- months flow inline with snap; "3 weeks
      //    out" is a flick, not taps through a grid.
      if (!_hasRange) {
        if (picked.isBefore(_start)) {
          _end = _start;
          _start = picked;
        } else {
          _end = picked;
        }
      } else {
        _start = picked;
        _end = picked;
      }
    });
  }

  void _setPreset(String preset) {
    final today = _clampDate(_dateOnly(DateTime.now()));
    late DateTime start;
    late DateTime end;
    switch (preset) {
      case 'This weekend':
        final daysUntilSaturday = (DateTime.saturday - today.weekday) % 7;
        start = today.add(Duration(days: daysUntilSaturday));
        end = start.add(const Duration(days: 1));
      case 'Next week':
        final daysUntilNextMonday = ((DateTime.monday - today.weekday) % 7) + 7;
        start = today.add(Duration(days: daysUntilNextMonday));
        end = start.add(const Duration(days: 6));
      case '10 days':
        start = today;
        end = today.add(const Duration(days: 9));
      case 'Just a day':
        start = today;
        end = today;
      default:
        start = today;
        end = today;
    }
    setState(() {
      _activePreset = preset;
      _start = _clampDate(start);
      _end = _clampDate(end);
      if (_end.isBefore(_start)) _end = _start;
    });
  }

  bool get _hasRange => !_sameDate(_start, _end);

  String get _summaryMain {
    final start = DateFormat('MMM d').format(_start);
    if (!_hasRange) return start;
    final end = _start.month == _end.month && _start.year == _end.year
        ? DateFormat('d').format(_end)
        : DateFormat('MMM d').format(_end);
    return '$start - $end';
  }

  String get _durationLabel {
    final days = VamoDateScrollerValue(start: _start, end: _end).durationDays;
    return days == 1 ? '1 day' : '$days days';
  }

  String get _ctaLabel {
    final value = VamoDateScrollerValue(start: _start, end: _end);
    if (!value.isSingle) return 'Use ${value.durationDays} days';
    final base = 'Use ${DateFormat('MMM d').format(_start)}';
    return _timesEnabled ? '$base · $_startTime' : base;
  }

  DateTime _clampDate(DateTime date) {
    if (date.isBefore(_firstDate)) return _firstDate;
    if (date.isAfter(_lastDate)) return _lastDate;
    return date;
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            decoration: const BoxDecoration(
              color: VamoTravelTokens.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: VamoTravelTokens.hairline),
                left: BorderSide(color: VamoTravelTokens.hairline),
                right: BorderSide(color: VamoTravelTokens.hairline),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x29120E16),
                  blurRadius: 50,
                  offset: Offset(0, -18),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: SizedBox(
                      width: 40,
                      height: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: VamoTravelTokens.border,
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Header(summary: _summaryMain, duration: _durationLabel),
                  const SizedBox(height: 14),
                  _PresetRow(
                    activePreset: _activePreset,
                    onSelected: _setPreset,
                  ),
                  const SizedBox(height: 14),
                  _MonthCarousel(
                    firstDate: _firstDate,
                    lastDate: _lastDate,
                    start: _start,
                    end: _end,
                    onDayTap: _tapDay,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '‹ scroll months · tap a day to start · tap another for the range ›',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: VamoTravelTokens.mute2,
                      fontSize: 10.5,
                    ),
                  ),
                  if (widget.allowTimes) ...[
                    const SizedBox(height: 14),
                    _AddTimesToggle(
                      value: _timesEnabled,
                      onChanged: (value) =>
                          setState(() => _timesEnabled = value),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.topCenter,
                      child: _timesEnabled
                          ? Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _TimeLabel('START TIME'),
                                  _TimeRow(
                                    values: _times,
                                    selected: _startTime,
                                    onSelected: (value) =>
                                        setState(() => _startTime = value),
                                  ),
                                  if (_hasRange) ...[
                                    const SizedBox(height: 12),
                                    const _TimeLabel.rich(
                                      leading: 'END TIME',
                                      optional: ' · optional',
                                    ),
                                    _TimeRow(
                                      values: _times,
                                      selected: _endTime,
                                      onSelected: (value) =>
                                          setState(() => _endTime = value),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _PrimaryButton(
                    label: _ctaLabel,
                    onTap: () {
                      Navigator.of(context).pop(
                        VamoDateScrollerValue(
                          start: _start,
                          end: _end,
                          startTime: _timesEnabled ? _startTime : null,
                          endTime: _timesEnabled && _hasRange ? _endTime : null,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.summary, required this.duration});

  final String summary;
  final String duration;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'When?',
                style: TextStyle(
                  color: VamoTravelTokens.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Single day or a range',
                style: TextStyle(
                  color: VamoTravelTokens.mute,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              summary,
              style: const TextStyle(
                color: VamoTravelTokens.coral,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              duration,
              style: const TextStyle(
                color: VamoTravelTokens.mute,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.activePreset, required this.onSelected});

  static const _presets = [
    'This weekend',
    'Next week',
    '10 days',
    'Just a day',
  ];

  final String? activePreset;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 45,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final preset = _presets[index];
          final selected = preset == activePreset;
          return _Pill(
            label: preset,
            selected: selected,
            selectedColor: VamoTravelTokens.ink,
            unselectedColor: VamoTravelTokens.chipBg,
            selectedTextColor: Colors.white,
            unselectedTextColor: const Color(0xFF4A4F5B),
            borderRadius: 999,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            onTap: () => onSelected(preset),
          );
        },
      ),
    );
  }
}

class _MonthCarousel extends StatelessWidget {
  const _MonthCarousel({
    required this.firstDate,
    required this.lastDate,
    required this.start,
    required this.end,
    required this.onDayTap,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime start;
  final DateTime end;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final months = _monthsBetween(firstDate, lastDate);
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
        itemCount: months.length,
        separatorBuilder: (_, __) => const SizedBox(width: 20),
        itemBuilder: (context, index) {
          return _MonthStrip(
            month: months[index],
            firstDate: firstDate,
            lastDate: lastDate,
            start: start,
            end: end,
            onDayTap: onDayTap,
          );
        },
      ),
    );
  }
}

class _MonthStrip extends StatelessWidget {
  const _MonthStrip({
    required this.month,
    required this.firstDate,
    required this.lastDate,
    required this.start,
    required this.end,
    required this.onDayTap,
  });

  final DateTime month;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime start;
  final DateTime end;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final days = _daysForMonth(month, firstDate, lastDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('MMM yyyy').format(month).toUpperCase(),
          style: const TextStyle(
            color: VamoTravelTokens.slate,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            for (var i = 0; i < days.length; i++) ...[
              _DayCell(
                day: days[i],
                start: start,
                end: end,
                onTap: () => onDayTap(days[i]),
              ),
              if (i != days.length - 1) const SizedBox(width: 4),
            ],
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.start,
    required this.end,
    required this.onTap,
  });

  final DateTime day;
  final DateTime start;
  final DateTime end;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final startIndex = _dayIndex(start);
    final endIndex = _dayIndex(end);
    final dayIndex = _dayIndex(day);
    final edge = dayIndex == startIndex || dayIndex == endIndex;
    final inRange = dayIndex > startIndex && dayIndex < endIndex;
    final bg = edge
        ? VamoTravelTokens.ink
        : inRange
            ? VamoTravelTokens.rangeTint(VamoTravelTokens.coral)
            : VamoTravelTokens.chipBg;
    final fg = edge ? Colors.white : VamoTravelTokens.inkSoft;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 46,
        height: 58,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('E').format(day).characters.first,
              style: TextStyle(
                color: fg.withValues(alpha: 0.65),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${day.day}',
              style: TextStyle(
                color: fg,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: edge ? VamoTravelTokens.lime : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTimesToggle extends StatelessWidget {
  const _AddTimesToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: value ? VamoTravelTokens.addTimesBg : VamoTravelTokens.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: VamoTravelTokens.hairline),
        ),
        child: Row(
          children: [
            Icon(
              Icons.schedule,
              size: 20,
              color: value ? VamoTravelTokens.jade : VamoTravelTokens.mute2,
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add times',
                    style: TextStyle(
                      color: VamoTravelTokens.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Optional — most trips only need dates',
                    style: TextStyle(
                      color: VamoTravelTokens.mute,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            _SpecSwitch(
              value: value,
              activeColor: VamoTravelTokens.jadeBright,
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecSwitch extends StatelessWidget {
  const _SpecSwitch({required this.value, required this.activeColor});

  final bool value;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 40,
      height: 23,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? activeColor : VamoTravelTokens.borderDash,
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 19,
          height: 19,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel(this.text)
      : leading = null,
        optional = null;

  const _TimeLabel.rich({required this.leading, required this.optional})
      : text = null;

  final String? text;
  final String? leading;
  final String? optional;

  @override
  Widget build(BuildContext context) {
    final leadingText = leading;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: leadingText == null
          ? Text(
              text!,
              style: _labelStyle,
            )
          : RichText(
              text: TextSpan(
                style: _labelStyle,
                children: [
                  TextSpan(text: leadingText),
                  TextSpan(
                    text: optional,
                    style: _labelStyle.copyWith(
                      color: VamoTravelTokens.optionalText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  static const _labelStyle = TextStyle(
    color: VamoTravelTokens.slate,
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5,
  );
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final List<String> values;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final value = values[index];
          return _Pill(
            label: value,
            selected: value == selected,
            selectedColor: VamoTravelTokens.jade,
            unselectedColor: VamoTravelTokens.chipBg,
            selectedTextColor: Colors.white,
            unselectedTextColor: VamoTravelTokens.inkSoft,
            borderRadius: 11,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            onTap: () => onSelected(value),
          );
        },
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.selectedTextColor,
    required this.unselectedTextColor,
    required this.borderRadius,
    required this.padding,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final Color selectedTextColor;
  final Color unselectedTextColor;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: padding,
        decoration: BoxDecoration(
          color: selected ? selectedColor : unselectedColor,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: selected ? selectedTextColor : unselectedTextColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

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

List<DateTime> _monthsBetween(DateTime firstDate, DateTime lastDate) {
  final months = <DateTime>[];
  var cursor = DateTime(firstDate.year, firstDate.month);
  final last = DateTime(lastDate.year, lastDate.month);
  while (!cursor.isAfter(last)) {
    months.add(cursor);
    cursor = DateTime(cursor.year, cursor.month + 1);
  }
  return months;
}

List<DateTime> _daysForMonth(
  DateTime month,
  DateTime firstDate,
  DateTime lastDate,
) {
  final monthStart = DateTime(month.year, month.month);
  final monthEnd = DateTime(month.year, month.month + 1, 0);
  var startDay = 1;
  var endDay = monthEnd.day;
  if (monthStart.year == firstDate.year &&
      monthStart.month == firstDate.month) {
    startDay = firstDate.day;
  }
  if (monthStart.year == lastDate.year && monthStart.month == lastDate.month) {
    endDay = lastDate.day;
  }
  return [
    for (var day = startDay; day <= endDay; day++)
      DateTime(month.year, month.month, day),
  ];
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _addMonths(DateTime date, int months) =>
    DateTime(date.year, date.month + months, date.day);

int _dayIndex(DateTime date) => DateTime.utc(date.year, date.month, date.day)
    .difference(DateTime.utc(1970))
    .inDays;

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
