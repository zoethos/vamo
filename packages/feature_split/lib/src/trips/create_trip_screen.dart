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
  final _destinationFocusNode = FocusNode();

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
    _destinationController.addListener(_onDestinationEdited);
    _destinationFocusNode.addListener(_onDestinationFocusChanged);
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
    _destinationController.removeListener(_onDestinationEdited);
    _destinationFocusNode.removeListener(_onDestinationFocusChanged);
    _nameController.dispose();
    _destinationController.dispose();
    _destinationFocusNode.dispose();
    super.dispose();
  }

  void _onDestinationEdited() {
    if (mounted) setState(() {});
  }

  void _onDestinationFocusChanged() {
    if (mounted) setState(() {});
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
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: _CreateTripHeader(
                  title: labels.title,
                  saving: _saving,
                  onClose: () => context.pop(),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _TripTextField(
                      label: labels.nameLabel,
                      controller: _nameController,
                      hintText: labels.nameHint,
                      icon: Icons.edit,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return labels.nameRequired;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    _DestinationHeroField(
                      label: labels.destinationLabel,
                      controller: _destinationController,
                      focusNode: _destinationFocusNode,
                      hintText: labels.destinationHint,
                      suggestions: _destinationSuggestions(),
                      showSuggestions: _showDestinationSuggestions,
                      onSuggestionTap: _selectDestinationSuggestion,
                      onClear: _destinationController.text.trim().isEmpty
                          ? null
                          : _clearDestination,
                    ),
                    const SizedBox(height: 24),
                    _DateRow(
                      label: 'Dates',
                      value: _dateSummary(labels),
                      duration: _dateDurationLabel(),
                      onTap: _pickDates,
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
                    const SizedBox(height: 14),
                    _CurrencyDisclosureRow(
                      label: labels.currencyLabel,
                      value: _baseCurrency,
                      currencies: _currencies,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _baseCurrency = v ?? 'EUR'),
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
          createLabel: labels.submit,
          saving: _saving,
          onDraftWithAi: _draftWithAi,
          onCreate: _save,
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

  bool get _showDestinationSuggestions {
    final query = _destinationController.text.trim();
    return query.isNotEmpty || _destinationFocusNode.hasFocus;
  }

  List<_DestinationSuggestion> _destinationSuggestions() {
    final raw = _destinationController.text.trim();
    final query = raw.isEmpty ? 'amalfi' : raw;
    if (query.toLowerCase().contains('amalfi')) {
      return const [
        _DestinationSuggestion(
          name: 'Amalfi',
          meta: 'Town · Salerno, Italy',
          swatch: _DestinationSwatch.seaGold,
        ),
        _DestinationSuggestion(
          name: 'Amalfi Coast',
          meta: 'Region · Campania, Italy',
          swatch: _DestinationSwatch.sunset,
        ),
        _DestinationSuggestion(
          name: 'Amalfi (Positano area)',
          meta: 'Area · 16 km west',
          swatch: _DestinationSwatch.coast,
        ),
      ];
    }
    final title = _titleCase(query);
    return [
      _DestinationSuggestion(
        name: title,
        meta: 'Destination',
        swatch: _DestinationSwatch.seaGold,
      ),
      _DestinationSuggestion(
        name: '$title Coast',
        meta: 'Region suggestion',
        swatch: _DestinationSwatch.sunset,
      ),
      _DestinationSuggestion(
        name: '$title area',
        meta: 'Area suggestion',
        swatch: _DestinationSwatch.coast,
      ),
    ];
  }

  void _selectDestinationSuggestion(_DestinationSuggestion suggestion) {
    _destinationController.text = suggestion.name;
    _destinationController.selection = TextSelection.collapsed(
      offset: _destinationController.text.length,
    );
    _destinationFocusNode.unfocus();
  }

  void _clearDestination() {
    _destinationController.clear();
    _destinationFocusNode.requestFocus();
  }

  String _dateDurationLabel() {
    final start = _startDate;
    final end = _endDate;
    if (start == null || end == null) return '';
    final days = DateTime(end.year, end.month, end.day)
            .difference(DateTime(start.year, start.month, start.day))
            .inDays +
        1;
    return days <= 1 ? '1 day' : '$days days';
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

String _titleCase(String value) {
  return value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
      .join(' ');
}

enum _DestinationSwatch { seaGold, sunset, coast }

class _DestinationSuggestion {
  const _DestinationSuggestion({
    required this.name,
    required this.meta,
    required this.swatch,
  });

  final String name;
  final String meta;
  final _DestinationSwatch swatch;
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: value ? VamoTravelTokens.advancedBg : VamoTravelTokens.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value ? VamoTravelTokens.plum : VamoTravelTokens.border,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.tune, color: VamoTravelTokens.plum, size: 20),
            const SizedBox(width: 11),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      labels.toggleTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VamoTravelTokens.inkSoft,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  _AdvancedBadge(label: labels.toggleBadge),
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

class _AdvancedBadge extends StatelessWidget {
  const _AdvancedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: VamoTravelTokens.advancedPillBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: VamoTravelTokens.advancedPillBorder),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: VamoTravelTokens.plum,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CreateTripFooter extends StatelessWidget {
  const _CreateTripFooter({
    required this.labels,
    required this.createLabel,
    required this.saving,
    required this.onDraftWithAi,
    required this.onCreate,
  });

  final AdvancedTravelLabels labels;
  final String createLabel;
  final bool saving;
  final VoidCallback onDraftWithAi;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              flex: 155,
              child: _FooterButton(
                label: 'Draft with AI',
                icon: Icons.auto_awesome,
                background: VamoTravelTokens.lime,
                foreground: VamoTravelTokens.ink,
                fontWeight: FontWeight.w800,
                saving: saving,
                onTap: saving ? null : onDraftWithAi,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 100,
              child: _FooterButton(
                label: createLabel,
                background: VamoTravelTokens.ink,
                foreground: Colors.white,
                fontWeight: FontWeight.w700,
                saving: false,
                onTap: saving ? null : onCreate,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(
              color: VamoTravelTokens.mute2,
              fontSize: 11,
              height: 1.2,
            ),
            children: [
              TextSpan(text: 'AI drafts a plan you can edit · '),
              TextSpan(
                text: 'Create',
                style: TextStyle(
                  color: VamoTravelTokens.inkSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(text: ' makes the trip now'),
            ],
          ),
        ),
      ],
    );
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.fontWeight,
    required this.saving,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final Color background;
  final Color foreground;
  final FontWeight fontWeight;
  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.65 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(15),
            boxShadow: background == VamoTravelTokens.lime
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
          child: saving
              ? SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 19, color: foreground),
                      const SizedBox(width: 7),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 14.5,
                          fontWeight: fontWeight,
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
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
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
          ),
          Text(
            title,
            style: const TextStyle(
              color: VamoTravelTokens.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripTextField extends StatelessWidget {
  const _TripTextField({
    required this.label,
    required this.controller,
    required this.hintText,
    required this.icon,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormLabel(label),
        const SizedBox(height: 9),
        Container(
          decoration: BoxDecoration(
            color: VamoTravelTokens.surface,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: VamoTravelTokens.border, width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              Icon(icon, size: 20, color: VamoTravelTokens.mute2),
              const SizedBox(width: 11),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  validator: validator,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: hintText,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  style: const TextStyle(
                    color: VamoTravelTokens.ink,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                  cursorColor: VamoTravelTokens.plum,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DestinationHeroField extends StatelessWidget {
  const _DestinationHeroField({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.suggestions,
    required this.showSuggestions,
    required this.onSuggestionTap,
    required this.onClear,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final List<_DestinationSuggestion> suggestions;
  final bool showSuggestions;
  final ValueChanged<_DestinationSuggestion> onSuggestionTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final selectedName = controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _FormLabel(label)),
            const _AiResolvePill(),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: VamoTravelTokens.surface,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: VamoTravelTokens.plum, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: VamoTravelTokens.plum.withValues(alpha: 0.10),
                blurRadius: 0,
                spreadRadius: 3,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              const Icon(Icons.search, size: 21, color: VamoTravelTokens.plum),
              const SizedBox(width: 11),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: hintText,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  style: const TextStyle(
                    color: VamoTravelTokens.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                  cursorColor: VamoTravelTokens.plum,
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClear,
                  child: const Icon(
                    Icons.cancel_outlined,
                    size: 19,
                    color: VamoTravelTokens.mute2,
                  ),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.topCenter,
          child: showSuggestions
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    children: [
                      for (final suggestion in suggestions)
                        _DestinationSuggestionRow(
                          suggestion: suggestion,
                          selected: selectedName == suggestion.name,
                          onTap: () => onSuggestionTap(suggestion),
                        ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _DestinationSuggestionRow extends StatelessWidget {
  const _DestinationSuggestionRow({
    required this.suggestion,
    required this.selected,
    required this.onTap,
  });

  final _DestinationSuggestion suggestion;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFF3EFF6)
              : VamoTravelTokens.surface.withValues(alpha: 0.64),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _DestinationSwatchBox(swatch: suggestion.swatch),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    suggestion.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VamoTravelTokens.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    suggestion.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VamoTravelTokens.mute,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_outline,
                size: 24,
                color: VamoTravelTokens.plum,
              ),
          ],
        ),
      ),
    );
  }
}

class _DestinationSwatchBox extends StatelessWidget {
  const _DestinationSwatchBox({required this.swatch});

  final _DestinationSwatch swatch;

  @override
  Widget build(BuildContext context) {
    final colors = switch (swatch) {
      _DestinationSwatch.seaGold => const [
          Color(0xFF7FB3D5),
          Color(0xFFF5B64A),
        ],
      _DestinationSwatch.sunset => const [
          Color(0xFFF3A15F),
          Color(0xFFC44D7C),
        ],
      _DestinationSwatch.coast => const [
          Color(0xFF5AB8C7),
          Color(0xFFE7C858),
        ],
    };
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0x0F000000)),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.duration,
    required this.onTap,
  });

  final String label;
  final String value;
  final String duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormLabel(label),
        const SizedBox(height: 9),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
            decoration: BoxDecoration(
              color: VamoTravelTokens.surface,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: VamoTravelTokens.border, width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_month,
                  size: 21,
                  color: VamoTravelTokens.coral,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VamoTravelTokens.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (duration.isNotEmpty) ...[
                  Text(
                    duration,
                    style: const TextStyle(
                      color: VamoTravelTokens.mute2,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                const Icon(
                  Icons.chevron_right,
                  size: 19,
                  color: VamoTravelTokens.chevron,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CurrencyDisclosureRow extends StatelessWidget {
  const _CurrencyDisclosureRow({
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
    return Container(
      decoration: BoxDecoration(
        color: VamoTravelTokens.surface.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: VamoTravelTokens.hairline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        icon: const Icon(
          Icons.keyboard_arrow_down,
          color: VamoTravelTokens.mute2,
        ),
        decoration: InputDecoration(
          labelText: label.toUpperCase(),
          border: InputBorder.none,
          isDense: true,
        ),
        style: const TextStyle(
          color: VamoTravelTokens.inkSoft,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        items: currencies
            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _AiResolvePill extends StatelessWidget {
  const _AiResolvePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF3E9FA), Color(0xFFFBEEF3)],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: VamoTravelTokens.advancedPillBorder),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 14, color: VamoTravelTokens.plum),
          SizedBox(width: 5),
          Text(
            'AI resolve',
            style: TextStyle(
              color: VamoTravelTokens.plum,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: VamoTravelTokens.slate,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}
