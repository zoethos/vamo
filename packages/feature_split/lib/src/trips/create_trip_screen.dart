import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../snapshot/theme_resolver_repository.dart';
import '../travel/advanced_travel_labels.dart';
import '../travel/advanced_travel_section.dart';
import '../travel/route_draft_review_screen.dart';
import '../travel/travel_leg.dart';
import '../travel/trip_route_repository.dart';
import 'create_trip_labels.dart';
import 'trips_models.dart';
import 'trips_repository.dart';

/// Slice 1 — create a solo trip (invite friends lands in Slice 5).
class CreateTripScreen extends ConsumerStatefulWidget {
  const CreateTripScreen({super.key, required this.labels});

  final CreateTripLabels labels;

  @override
  ConsumerState<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends ConsumerState<CreateTripScreen> {
  late final FlowTracker _flowTracker;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _destinationController = TextEditingController();

  String _baseCurrency = 'EUR';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _saving = false;
  String? _dateRangeError;
  bool _advanced = false;
  Set<TravelMode> _modes = const {TravelMode.car, TravelMode.train};
  List<TravelLeg> _legs = const [];

  static const _currencies = kProfileCurrencies;

  @override
  void initState() {
    super.initState();
    _flowTracker = FlowTracker(
      flow: 'create_trip',
      analytics: ref.read(analyticsProvider),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDefaultCurrency());
  }

  Future<void> _loadDefaultCurrency() async {
    try {
      final profile = await ref.read(userProfileProvider.future);
      if (mounted) setState(() => _baseCurrency = profile.baseCurrency);
    } catch (error, stackTrace) {
      // Profile unavailable before first sign-in edge case.
      reportAndLog(
        error,
        stackTrace,
        screen: 'create_trip',
        action: 'load_default_currency',
        severity: ActionFailureSeverity.degraded,
        analytics: ref.read(analyticsProvider),
      );
    }
  }

  @override
  void dispose() {
    _flowTracker.abandonIfIncomplete();
    _nameController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    return Scaffold(
      backgroundColor: VamoTravelTokens.appBg,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 6),
                child: _CreateTripHeader(
                  title: labels.title,
                  saving: _saving,
                  onClose: () => context.pop(),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _CompactTextCard(
                      label: labels.nameLabel,
                      controller: _nameController,
                      hintText: labels.nameHint,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return labels.nameRequired;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _CompactTextCard(
                            label: labels.destinationLabel,
                            controller: _destinationController,
                            hintText: labels.destinationHint,
                            textCapitalization: TextCapitalization.words,
                            trailing: _AiModeChip(
                              label: labels.advanced.draftWithAiBadge,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _DateSummaryCard(
                            label: 'Dates',
                            value: _dateSummary(labels),
                            onTap: _pickDates,
                          ),
                        ),
                      ],
                    ),
                    if (_dateRangeError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _dateRangeError!,
                        style: const TextStyle(
                          color: VamoTravelTokens.destructive,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _CurrencyCard(
                      label: labels.currencyLabel,
                      value: _baseCurrency,
                      currencies: _currencies,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _baseCurrency = v ?? 'EUR'),
                    ),
                    const SizedBox(height: 14),
                    _ContextSummaryRow(
                      destination: _destinationSummary(),
                      dates: _dateSummary(labels),
                    ),
                    const SizedBox(height: 14),
                    _AdvancedToggle(
                      labels: labels.advanced,
                      value: _advanced,
                      onChanged:
                          _saving ? null : (v) => setState(() => _advanced = v),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.topCenter,
                      child: _advanced
                          ? Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: AdvancedTravelSection(
                                labels: labels.advanced,
                                modes: _modes,
                                onModesChanged: (modes) =>
                                    setState(() => _modes = modes),
                                legs: _legs,
                                onChanged: (legs) =>
                                    setState(() => _legs = legs),
                                unit: ref.watch(distanceUnitProvider),
                                tripStart: _startDate,
                                tripEnd: _endDate,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: _CreateTripFooter(
          labels: labels.advanced,
          advanced: _advanced,
          saving: _saving,
          onDraftWithAi: _draftWithAi,
          onPlanMyself: _save,
        ),
      ),
    );
  }

  String _dateSummary(CreateTripLabels labels) {
    if (_startDate == null && _endDate == null) return labels.startDate;
    final fmt = DateFormat('MMM d');
    if (_startDate != null && _endDate != null) {
      final sameMonth = _startDate!.month == _endDate!.month &&
          _startDate!.year == _endDate!.year;
      return sameMonth
          ? '${fmt.format(_startDate!)} – ${_endDate!.day}'
          : '${fmt.format(_startDate!)} – ${fmt.format(_endDate!)}';
    }
    return fmt.format((_startDate ?? _endDate)!);
  }

  String _destinationSummary() {
    final destination = _destinationController.text.trim();
    return destination.isEmpty ? 'Amalfi Coast' : destination;
  }

  Future<void> _pickDates() async {
    final result = await showVamoDateScroller(
      context: context,
      initialStart: _startDate,
      initialEnd: _endDate,
      allowTimes: false,
    );
    if (!mounted || result == null) return;
    setState(() {
      _startDate = result.start;
      _endDate = result.end;
      _validateDateRange();
    });
  }

  void _validateDateRange() {
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      _dateRangeError = widget.labels.endBeforeStart;
    } else {
      _dateRangeError = null;
    }
  }

  /// Validates the form and creates the trip; returns its id, or null if
  /// validation failed or creation errored (error surfaced to the user).
  Future<String?> _createTrip() async {
    if (!_formKey.currentState!.validate()) return null;
    _validateDateRange();
    if (_dateRangeError != null) {
      setState(() {});
      return null;
    }
    final destination = _destinationController.text.trim();
    try {
      final id = await ref.read(tripsRepositoryProvider).createTrip(
            CreateTripInput(
              name: _nameController.text,
              destination: destination.isEmpty ? null : destination,
              startDate: _isoDate(_startDate),
              endDate: _isoDate(_endDate),
              baseCurrency: _baseCurrency,
            ),
          );
      unawaited(
        ref.read(themeResolverRepositoryProvider).resolveForTrip(
              tripId: id,
              destination: destination,
            ),
      );
      return id;
    } catch (e) {
      if (mounted) {
        showActionError(
          context,
          ref,
          screen: 'create_trip',
          action: 'create_trip',
          error: e,
        );
      }
      return null;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final id = await _createTrip();
      if (id == null || !mounted) return;
      _flowTracker.complete();
      context.go(AppRoutes.trip(id));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Creates the trip, then asks the AI to draft a route and opens the review
  /// screen. Gating/failure degrade to the trip home — the trip still exists.
  Future<void> _draftWithAi() async {
    setState(() => _saving = true);
    try {
      final id = await _createTrip();
      if (id == null || !mounted) return;
      final destination = _destinationController.text.trim();
      final result = await ref.read(tripRouteRepositoryProvider).draftRoute(
            tripId: id,
            destination: destination,
            tripStart: _isoDate(_startDate),
            tripEnd: _isoDate(_endDate),
            modes: _modes.toList(growable: false),
            legs: _legs,
          );
      if (!mounted) return;
      _flowTracker.complete();
      final advanced = widget.labels.advanced;
      switch (result) {
        case RouteDraftSuccess(:final draft):
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => RouteDraftReviewScreen(
                tripId: id,
                draft: draft,
                labels: advanced,
              ),
            ),
          );
          if (mounted) context.go(AppRoutes.trip(id));
        case RouteDraftGated():
          _toast(advanced.draftGatedMessage);
          context.go(AppRoutes.trip(id));
        case RouteDraftUnavailable():
          _toast(advanced.draftFailedMessage);
          context.go(AppRoutes.trip(id));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String? _isoDate(DateTime? d) =>
      d == null ? null : DateFormat('yyyy-MM-dd').format(d);
}

class _AdvancedToggle extends StatelessWidget {
  const _AdvancedToggle({
    required this.labels,
    required this.value,
    required this.onChanged,
  });

  final AdvancedTravelLabels labels;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: value ? VamoTravelTokens.advancedBg : VamoTravelTokens.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value ? VamoTravelTokens.plum : VamoTravelTokens.border,
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            const Icon(Icons.tune, color: VamoTravelTokens.plum, size: 21),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 7,
                    children: [
                      Text(
                        labels.toggleTitle,
                        style: const TextStyle(
                          color: VamoTravelTokens.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: VamoTravelTokens.advancedPillBg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: VamoTravelTokens.advancedPillBorder,
                          ),
                        ),
                        child: Text(
                          labels.toggleBadge.toUpperCase(),
                          style: const TextStyle(
                            color: VamoTravelTokens.plum,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    labels.toggleSubtitle,
                    style: const TextStyle(
                      color: VamoTravelTokens.mute,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 11),
            _SpecSwitch(value: value, activeColor: VamoTravelTokens.plum),
          ],
        ),
      ),
    );
  }
}

class _ContextSummaryRow extends StatelessWidget {
  const _ContextSummaryRow({required this.destination, required this.dates});

  final String destination;
  final String dates;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ContextSummaryCard(
            label: 'Destination',
            value: destination,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _ContextSummaryCard(
            label: 'Dates',
            value: dates,
          ),
        ),
      ],
    );
  }
}

class _ContextSummaryCard extends StatelessWidget {
  const _ContextSummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: VamoTravelTokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VamoTravelTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: VamoTravelTokens.slate,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: VamoTravelTokens.ink,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateTripFooter extends StatelessWidget {
  const _CreateTripFooter({
    required this.labels,
    required this.advanced,
    required this.saving,
    required this.onDraftWithAi,
    required this.onPlanMyself,
  });

  final AdvancedTravelLabels labels;
  final bool advanced;
  final bool saving;
  final VoidCallback onDraftWithAi;
  final VoidCallback onPlanMyself;

  @override
  Widget build(BuildContext context) {
    final draftLabel = advanced ? labels.draftWithAi : 'Draft my plan with AI';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: AlignmentDirectional.topEnd,
          children: [
            _SpecButton(
              label: draftLabel,
              icon: Icons.auto_awesome,
              filled: true,
              busy: saving,
              onTap: saving ? null : onDraftWithAi,
            ),
            PositionedDirectional(
              end: 12,
              top: -9,
              child: _VamoAiBadge(label: labels.draftWithAiBadge),
            ),
          ],
        ),
        const SizedBox(height: 9),
        _SpecButton(
          label: labels.planItMyself,
          icon: Icons.edit_note,
          filled: false,
          busy: false,
          onTap: saving ? null : onPlanMyself,
        ),
        const SizedBox(height: 8),
        Text(
          labels.aiFootnote,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: VamoTravelTokens.mute2,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

class _SpecButton extends StatelessWidget {
  const _SpecButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.65 : 1,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: filled ? 15 : 13),
          decoration: BoxDecoration(
            color: filled ? VamoTravelTokens.lime : VamoTravelTokens.surface,
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(color: VamoTravelTokens.borderDash, width: 1.5),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: VamoTravelTokens.lime.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: VamoTravelTokens.ink,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: filled ? 20 : 19,
                      color: filled
                          ? VamoTravelTokens.ink
                          : VamoTravelTokens.slate,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: filled
                              ? VamoTravelTokens.ink
                              : VamoTravelTokens.inkSoft,
                          fontSize: filled ? 15 : 14,
                          fontWeight:
                              filled ? FontWeight.w800 : FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
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

class _CreateTripHeader extends StatelessWidget {
  const _CreateTripHeader({
    required this.title,
    required this.saving,
    required this.onClose,
  });

  final String title;
  final bool saving;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: saving ? null : onClose,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.close,
              size: 24,
              color: VamoTravelTokens.ink,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          title,
          style: const TextStyle(
            color: VamoTravelTokens.ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _CompactTextCard extends StatelessWidget {
  const _CompactTextCard({
    required this.label,
    required this.controller,
    required this.hintText,
    this.validator,
    this.textCapitalization = TextCapitalization.sentences,
    this.trailing,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final FormFieldValidator<String>? validator;
  final TextCapitalization textCapitalization;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              validator: validator,
              textCapitalization: textCapitalization,
              decoration: InputDecoration(
                labelText: label.toUpperCase(),
                hintText: hintText,
                border: InputBorder.none,
                isDense: true,
              ),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _DateSummaryCard extends StatelessWidget {
  const _DateSummaryCard({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: VamoTravelTokens.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: VamoTravelTokens.border),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VamoTravelTokens.slate,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VamoTravelTokens.ink,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyCard extends StatelessWidget {
  const _CurrencyCard({
    required this.label,
    required this.value,
    required this.currencies,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> currencies;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label.toUpperCase(),
          border: InputBorder.none,
          isDense: true,
        ),
        items: currencies
            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _AiModeChip extends StatelessWidget {
  const _AiModeChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final accent = VamoPlanTypeColors.lodging;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _VamoAiBadge extends StatelessWidget {
  const _VamoAiBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: const BoxDecoration(
        color: VamoTravelTokens.plum,
        borderRadius: BorderRadius.all(Radius.circular(999)),
        boxShadow: [
          BoxShadow(
            color: Color(0x666A2D6F),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '★ ${label.toUpperCase()}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
