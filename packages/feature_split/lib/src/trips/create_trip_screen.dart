import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../snapshot/theme_resolver_repository.dart';
import '../travel/advanced_travel_labels.dart';
import '../travel/advanced_travel_section.dart';
import '../travel/travel_leg.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: Text(labels.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _saving ? null : () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              labels.headline,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              labels.subtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: labels.nameLabel,
                hintText: labels.nameHint,
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return labels.nameRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _destinationController,
              decoration: InputDecoration(
                labelText: labels.destinationLabel,
                hintText: labels.destinationHint,
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _baseCurrency,
              decoration: InputDecoration(labelText: labels.currencyLabel),
              items: _currencies
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _baseCurrency = v ?? 'EUR'),
            ),
            const SizedBox(height: 16),
            _DateRow(
              label: labels.startDate,
              value: _startDate,
              onPick: _pickStart,
              optionalHint: labels.startDate,
            ),
            const SizedBox(height: 12),
            _DateRow(
              label: labels.endDate,
              value: _endDate,
              onPick: _pickEnd,
              optionalHint: labels.endDate,
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
            const SizedBox(height: 24),
            _AdvancedToggle(
              labels: labels.advanced,
              value: _advanced,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _advanced = v),
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
            const SizedBox(height: 32),
            ..._buildCtas(labels),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCtas(CreateTripLabels labels) {
    final saveButton = FilledButton(
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
          : Text(_advanced ? labels.advanced.planItMyself : labels.submit),
    );

    if (!_advanced) return [saveButton];

    // "Draft route with AI" is the headline CTA but is wired in a later slice;
    // for now it announces itself and the manual path sits right beside it.
    return [
      FilledButton.icon(
        onPressed: _saving
            ? null
            : () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(labels.advanced.draftComingSoon)),
                ),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.goLime,
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(52),
        ),
        icon: const Icon(Icons.auto_awesome),
        label: Text(labels.advanced.draftWithAi),
      ),
      const SizedBox(height: 12),
      saveButton,
      const SizedBox(height: 12),
      Text(
        labels.advanced.aiFootnote,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.neutralMid),
      ),
    ];
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _validateDateRange();
    if (_dateRangeError != null) {
      setState(() {});
      return;
    }

    setState(() => _saving = true);
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
      if (!mounted) return;
      _flowTracker.complete();
      context.go(AppRoutes.trip(id));
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'create_trip',
        action: 'create_trip',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.deepPlum.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.deepPlum.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          const Icon(Icons.tune, color: AppColors.deepPlum),
          const SizedBox(width: 12),
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
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
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
                        color: AppColors.deepPlum.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        labels.toggleBadge.toUpperCase(),
                        style: textTheme.labelSmall?.copyWith(
                          color: AppColors.deepPlum,
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
                    color: AppColors.graphite,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.deepPlum,
          ),
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onPick,
    required this.optionalHint,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final String optionalHint;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final formatted = value == null ? null : DateFormat.yMMMd().format(value!);
    return OutlinedButton(
      onPressed: onPick,
      style: OutlinedButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        foregroundColor: colors.onSurface,
        side: BorderSide(color: colors.border),
      ),
      child: Text(formatted ?? optionalHint),
    );
  }
}
