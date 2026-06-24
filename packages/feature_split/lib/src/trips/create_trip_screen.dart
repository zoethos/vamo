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
    final colors = context.vamoColors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
              _CreateTripHeader(
                title: labels.title,
                saving: _saving,
                onClose: () => context.pop(),
              ),
              const SizedBox(height: 22),
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
                      trailing:
                          _AiModeChip(label: labels.advanced.draftWithAiBadge),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _DateSummaryCard(
                      label: labels.endDate,
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
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
              const SizedBox(height: 20),
              _AdvancedToggle(
                labels: labels.advanced,
                value: _advanced,
                onChanged:
                    _saving ? null : (v) => setState(() => _advanced = v),
              ),
              if (_advanced) ...[
                const SizedBox(height: 20),
                AdvancedTravelSection(
                  labels: labels.advanced,
                  legs: _legs,
                  onChanged: (legs) => setState(() => _legs = legs),
                  unit: ref.watch(distanceUnitProvider),
                  datePickerLabels: VamoDatePickerLabels(
                    cancel: labels.datePickerCancel,
                    skip: labels.datePickerSkip,
                    select: labels.datePickerSelect,
                  ),
                  tripStart: _startDate,
                  tripEnd: _endDate,
                ),
              ],
              const SizedBox(height: 28),
              ..._buildCtas(labels),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCtas(CreateTripLabels labels) {
    final manualButton = _advanced
        ? OutlinedButton.icon(
            onPressed: _saving ? null : _save,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              foregroundColor: context.vamoColors.onSurface,
              side: BorderSide(color: context.vamoColors.border),
            ),
            icon: const Icon(Icons.format_list_bulleted_add, size: 18),
            label: Text(labels.advanced.planItMyself),
          )
        : FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(labels.submit),
          );

    if (!_advanced) return [manualButton];

    // "Draft route with AI" is the headline CTA; the manual path sits beside it.
    return [
      Stack(
        clipBehavior: Clip.none,
        alignment: AlignmentDirectional.topEnd,
        children: [
          FilledButton.icon(
            onPressed: _saving ? null : _draftWithAi,
            style: FilledButton.styleFrom(
              backgroundColor: context.vamoColors.action,
              foregroundColor: context.vamoColors.onAction,
              minimumSize: const Size.fromHeight(64),
              textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            icon: const Icon(Icons.auto_awesome),
            label: Text(labels.advanced.draftWithAi),
          ),
          PositionedDirectional(
            end: 18,
            top: -11,
            child: _VamoAiBadge(label: labels.advanced.draftWithAiBadge),
          ),
        ],
      ),
      const SizedBox(height: 12),
      manualButton,
      const SizedBox(height: 12),
      Text(
        labels.advanced.aiFootnote,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: context.vamoColors.onSurfaceMuted),
      ),
    ];
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

  Future<void> _pickDates() async {
    await _pickStart();
    if (!mounted || _startDate == null) return;
    await _pickEnd();
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

  Future<void> _pickStart() async {
    final result = await showVamoDatePicker(
      context: context,
      labels: VamoDatePickerLabels(
        cancel: widget.labels.datePickerCancel,
        skip: widget.labels.datePickerSkip,
        select: widget.labels.datePickerSelect,
      ),
      initialDate: _startDate,
    );
    if (!mounted) return;
    switch (result.outcome) {
      case VamoDatePickOutcome.skipped:
        setState(() {
          _startDate = null;
          _validateDateRange();
        });
      case VamoDatePickOutcome.selected:
        setState(() {
          _startDate = result.date;
          _validateDateRange();
        });
      case VamoDatePickOutcome.cancelled:
        break;
    }
  }

  Future<void> _pickEnd() async {
    final result = await showVamoDatePicker(
      context: context,
      labels: VamoDatePickerLabels(
        cancel: widget.labels.datePickerCancel,
        skip: widget.labels.datePickerSkip,
        select: widget.labels.datePickerSelect,
      ),
      initialDate: _endDate ?? _startDate,
      firstDate: _startDate ?? DateTime(2020),
    );
    if (!mounted) return;
    switch (result.outcome) {
      case VamoDatePickOutcome.skipped:
        setState(() {
          _endDate = null;
          _validateDateRange();
        });
      case VamoDatePickOutcome.selected:
        setState(() {
          _endDate = result.date;
          _validateDateRange();
        });
      case VamoDatePickOutcome.cancelled:
        break;
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
    final colors = context.vamoColors;
    final accent = VamoPlanTypeColors.lodging;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 14, 18),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.tune, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        labels.toggleTitle,
                        style: textTheme.titleMedium?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        labels.toggleBadge.toUpperCase(),
                        style: textTheme.labelSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  labels.toggleSubtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: accent,
          ),
        ],
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
        IconButton(
          onPressed: saving ? null : onClose,
          icon: const Icon(Icons.close),
          color: context.vamoColors.onSurface,
        ),
        const SizedBox(width: 4),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: context.vamoColors.onSurface,
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
    final colors = context.vamoColors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border.withValues(alpha: 0.5)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceMuted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
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
    final accent = VamoPlanTypeColors.lodging;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '★ ${label.toUpperCase()}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
