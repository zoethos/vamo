import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../places/place_geocode.dart';
import '../snapshot/theme_resolver_repository.dart';
import '../travel/advanced_travel_labels.dart';
import '../travel/advanced_travel_section.dart';
import '../travel/route_draft_review_screen.dart';
import '../travel/travel_leg.dart';
import '../travel/trip_route_repository.dart';
import 'create_trip_labels.dart';
import 'destination_visual_repository.dart';
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
  bool _destinationResolving = false;
  String? _destinationResolveMessage;
  bool _destinationResolveIsError = false;
  _DestinationSuggestion? _resolvedDestination;

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
    final query = _destinationController.text.trim();
    final resolved = _resolvedDestination;
    if (resolved != null && query != resolved.name) {
      _resolvedDestination = null;
      _destinationResolveMessage = null;
      _destinationResolveIsError = false;
    }
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
                      resolving: _destinationResolving,
                      resolveMessage: _destinationResolveMessage,
                      resolveMessageIsError: _destinationResolveIsError,
                      onResolve:
                          _destinationResolving ? null : _resolveDestination,
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
    final suggestion = _resolvedDestination;
    return suggestion == null ? const [] : [suggestion];
  }

  void _selectDestinationSuggestion(_DestinationSuggestion suggestion) {
    _destinationController.text = suggestion.name;
    _destinationController.selection = TextSelection.collapsed(
      offset: _destinationController.text.length,
    );
    _destinationFocusNode.unfocus();
  }

  Future<void> _resolveDestination() async {
    final query = _destinationController.text.trim();
    if (query.length < 3) {
      setState(() {
        _destinationResolveMessage = 'Type at least 3 characters to resolve.';
        _destinationResolveIsError = true;
      });
      _destinationFocusNode.requestFocus();
      return;
    }

    setState(() {
      _destinationResolving = true;
      _destinationResolveMessage = null;
      _destinationResolveIsError = false;
      _resolvedDestination = null;
    });

    final resolved = await resolveDestination(query);
    if (!mounted) return;

    if (_destinationController.text.trim() != query) {
      setState(() => _destinationResolving = false);
      return;
    }

    if (resolved == null) {
      setState(() {
        _destinationResolving = false;
        _destinationResolveMessage =
            'No destination match found. Check the spelling or add country.';
        _destinationResolveIsError = true;
      });
      return;
    }

    final visual = await ref.read(destinationVisualRepositoryProvider).resolve(
          destination: resolved.label,
          lat: resolved.coords.lat,
          lng: resolved.coords.lng,
          observationKind: 'manual_find',
        );
    if (!mounted) return;

    final suggestion = _DestinationSuggestion(
      name: resolved.label,
      meta: visual?.subtitle ??
          resolved.subtitle ??
          '${resolved.coords.lat.toStringAsFixed(4)}, '
              '${resolved.coords.lng.toStringAsFixed(4)}',
      swatch: _DestinationSwatch.seaGold,
      coords: resolved.coords,
      visual: visual,
    );
    setState(() {
      _destinationResolving = false;
      _destinationResolveMessage = null;
      _destinationResolveIsError = false;
      _resolvedDestination = suggestion;
    });
    _destinationController.text = suggestion.name;
    _destinationController.selection = TextSelection.collapsed(
      offset: suggestion.name.length,
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
      unawaited(
        _applyDestinationBackground(
          tripId: id,
          destination: destination,
          resolved: _resolvedDestination,
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
  /// screen. Gating/failure roll back the just-created draft trip.
  Future<void> _draftWithAi() async {
    setState(() => _saving = true);
    try {
      final trips = ref.read(tripsRepositoryProvider);
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
      final advanced = widget.labels.advanced;
      switch (result) {
        case RouteDraftSuccess(:final draft):
          _flowTracker.complete();
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => RouteDraftReviewScreen(
                tripId: id,
                title: _proposalTitle(),
                subtitle: _proposalSubtitle(destination),
                draft: draft,
                labels: advanced,
              ),
            ),
          );
          if (mounted) context.go(AppRoutes.trip(id));
        case RouteDraftGated():
          await trips.discardNewTripAfterDraftFailure(id);
          if (!mounted) return;
          _toast(advanced.draftGatedMessage);
        case RouteDraftUnavailable():
          await trips.discardNewTripAfterDraftFailure(id);
          if (!mounted) return;
          _toast(advanced.draftFailedMessage);
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

  Future<void> _applyDestinationBackground({
    required String tripId,
    required String destination,
    required _DestinationSuggestion? resolved,
  }) async {
    final trips = ref.read(tripsRepositoryProvider);
    final visuals = ref.read(destinationVisualRepositoryProvider);
    final analytics = ref.read(analyticsProvider);
    try {
      var visual = resolved?.visual;
      if (visual == null || !visual.hasImage) {
        final query = destination.trim();
        if (query.isEmpty) return;
        visual = await visuals.resolve(
          destination: resolved?.name ?? query,
          lat: resolved?.coords?.lat,
          lng: resolved?.coords?.lng,
          tripId: tripId,
          observationKind: 'create_trip_background',
        );
      }
      if (visual == null || !visual.hasImage) return;
      final bytes = visual.imageBytes;
      if (bytes != null) {
        await trips.setTripBackgroundBytes(
          tripId: tripId,
          sourceName: visual.sourceName,
          bytes: bytes,
        );
        return;
      }
      final imageUrl = visual.imageUrl;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        await trips.setTripBackgroundFromUrl(
          tripId: tripId,
          imageUrl: imageUrl,
        );
      }
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'create_trip',
        action: 'apply_destination_background',
        severity: ActionFailureSeverity.degraded,
        analytics: analytics,
      );
    }
  }

  String _proposalTitle() {
    final name = _nameController.text.trim();
    return name.isEmpty ? widget.labels.title : name;
  }

  String _proposalSubtitle(String destination) {
    final destinationText = _resolvedDestination?.name ??
        (destination.isEmpty ? widget.labels.destinationLabel : destination);
    final parts = <String>[destinationText];
    final date = _proposalDateRangeLabel();
    if (date != null) parts.add(date);
    final duration = _dateDurationLabel();
    if (duration.isNotEmpty) parts.add(duration);
    return parts.join(' · ');
  }

  String? _proposalDateRangeLabel() {
    final start = _startDate;
    final end = _endDate;
    final fmt = DateFormat('MMM d');
    if (start == null && end == null) return null;
    if (start != null && end != null) {
      final sameMonth = start.month == end.month && start.year == end.year;
      return sameMonth
          ? '${fmt.format(start)}–${end.day}'
          : '${fmt.format(start)}–${fmt.format(end)}';
    }
    return fmt.format((start ?? end)!);
  }
}

enum _DestinationSwatch { seaGold, sunset, coast }

class _DestinationSuggestion {
  const _DestinationSuggestion({
    required this.name,
    required this.meta,
    required this.swatch,
    this.coords,
    this.visual,
  });

  final String name;
  final String meta;
  final _DestinationSwatch swatch;
  final GeocodeCoords? coords;
  final DestinationVisual? visual;
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
              child: Text(
                labels.toggleTitle,
                maxLines: 2,
                overflow: TextOverflow.visible,
                style: const TextStyle(
                  color: VamoTravelTokens.inkSoft,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
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
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
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
              Expanded(
                child: TextFormField(
                  controller: controller,
                  validator: validator,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _singleShapeInputDecoration(hintText),
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
    required this.resolving,
    required this.resolveMessage,
    required this.resolveMessageIsError,
    required this.onResolve,
    required this.onSuggestionTap,
    required this.onClear,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final List<_DestinationSuggestion> suggestions;
  final bool showSuggestions;
  final bool resolving;
  final String? resolveMessage;
  final bool resolveMessageIsError;
  final VoidCallback? onResolve;
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
            _DestinationFindPill(
              resolving: resolving,
              onTap: onResolve,
            ),
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
              Expanded(
                child: TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  onFieldSubmitted: (_) => onResolve?.call(),
                  textCapitalization: TextCapitalization.words,
                  decoration: _singleShapeInputDecoration(hintText),
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
          child: resolving
              ? const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: _DestinationResolveMessage(
                    message: 'Resolving destination...',
                    isError: false,
                    loading: true,
                  ),
                )
              : showSuggestions && suggestions.isNotEmpty
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
                  : resolveMessage != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _DestinationResolveMessage(
                            message: resolveMessage!,
                            isError: resolveMessageIsError,
                          ),
                        )
                      : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _DestinationResolveMessage extends StatelessWidget {
  const _DestinationResolveMessage({
    required this.message,
    required this.isError,
    this.loading = false,
  });

  final String message;
  final bool isError;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final color =
        isError ? VamoTravelTokens.destructive : VamoTravelTokens.mute;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isError
            ? VamoTravelTokens.destructive.withValues(alpha: 0.08)
            : VamoTravelTokens.surface.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError
              ? VamoTravelTokens.destructive.withValues(alpha: 0.25)
              : VamoTravelTokens.hairline,
        ),
      ),
      child: Row(
        children: [
          if (loading)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          else
            Icon(
              isError ? Icons.info_outline : Icons.check_circle_outline,
              size: 17,
              color: color,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
            _DestinationVisualBox(suggestion: suggestion),
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

class _DestinationVisualBox extends StatelessWidget {
  const _DestinationVisualBox({required this.suggestion});

  final _DestinationSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final visual = suggestion.visual;
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        width: 48,
        height: 48,
        child: visual?.imageBytes != null
            ? Image.memory(
                visual!.imageBytes!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _DestinationSwatchBox(swatch: suggestion.swatch),
              )
            : visual?.imageUrl != null
                ? Image.network(
                    visual!.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _DestinationSwatchBox(swatch: suggestion.swatch),
                  )
                : _DestinationSwatchBox(swatch: suggestion.swatch),
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

class _DestinationFindPill extends StatelessWidget {
  const _DestinationFindPill({
    required this.resolving,
    required this.onTap,
  });

  final bool resolving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Find destination',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: resolving ? null : onTap,
        child: Opacity(
          opacity: onTap == null && !resolving ? 0.52 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF3E9FA), Color(0xFFFBEEF3)],
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: VamoTravelTokens.advancedPillBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (resolving)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: VamoTravelTokens.plum,
                    ),
                  )
                else
                  const Icon(
                    Icons.auto_awesome,
                    size: 14,
                    color: VamoTravelTokens.plum,
                  ),
                const SizedBox(width: 5),
                Text(
                  resolving ? 'Finding' : 'Find',
                  style: const TextStyle(
                    color: VamoTravelTokens.plum,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration _singleShapeInputDecoration(String hintText) {
  return InputDecoration(
    hintText: hintText,
    filled: false,
    fillColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(vertical: 15),
  );
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
