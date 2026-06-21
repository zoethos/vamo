import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../expenses/expense_consent_providers.dart';
import '../expenses/money_format.dart';
import 'trip_budget.dart';
import 'trip_budget_labels.dart';
import 'trip_fx_models.dart';
import 'trips_models.dart';
import 'trips_providers.dart';
import 'trips_repository.dart';

/// Trip budget + FX settings (D3/D4). Writes hidden for members / read-only trips.
class TripSettingsScreen extends ConsumerStatefulWidget {
  const TripSettingsScreen({
    super.key,
    required this.tripId,
    required this.labels,
  });

  final String tripId;
  final TripBudgetLabels labels;

  @override
  ConsumerState<TripSettingsScreen> createState() => _TripSettingsScreenState();
}

class _TripSettingsScreenState extends ConsumerState<TripSettingsScreen> {
  static const _currencies = ['EUR', 'USD', 'GBP', 'CHF'];

  final _budgetAmountController = TextEditingController();
  TripBudgetMode _mode = TripBudgetMode.none;
  bool _savingBudget = false;
  String? _capturingCurrency;
  bool _budgetFormSynced = false;

  DateTime? _startDate;
  DateTime? _endDate;
  bool _datesFormSynced = false;
  bool _savingDates = false;
  String? _dateRangeError;
  bool _offloadingMedia = false;
  bool _savingSubtrips = false;

  @override
  void dispose() {
    _budgetAmountController.dispose();
    super.dispose();
  }

  void _syncBudgetForm(TripDetail detail) {
    if (_budgetFormSynced) return;
    _budgetFormSynced = true;
    _mode = TripBudgetMode.parse(detail.budgetMode);
    if (detail.budgetCents != null) {
      _budgetAmountController.text =
          (detail.budgetCents! / 100).toStringAsFixed(2);
    }
  }

  void _syncDatesForm(TripDetail detail) {
    if (_datesFormSynced) return;
    _datesFormSynced = true;
    _startDate = _parseIsoDate(detail.startDate);
    _endDate = _parseIsoDate(detail.endDate);
  }

  static DateTime? _parseIsoDate(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso);
  }

  static String? _isoDate(DateTime? d) =>
      d == null ? null : DateFormat('yyyy-MM-dd').format(d);

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(tripDetailProvider(widget.tripId));
    final fxRates = ref.watch(tripFxRatesProvider(widget.tripId));
    final burnDown = ref.watch(tripBudgetBurnDownProvider(widget.tripId));
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final role = ref.watch(
      currentMemberRoleProvider(
        (tripId: widget.tripId, userId: currentUserId),
      ),
    );

    return trip.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: Text(widget.labels.settingsTitle)),
        body: const Center(child: Text('Could not load trip')),
      ),
      data: (detail) {
        if (detail == null) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.labels.settingsTitle)),
            body: const Center(child: Text('Trip not found')),
          );
        }

        _syncBudgetForm(detail);
        _syncDatesForm(detail);

        final readOnly = isTripReadOnly(TripLifecycle.parse(detail.lifecycle));
        final canManage = canManageTripBudgetAndFx(
          tripReadOnly: readOnly,
          memberRole: role,
        );

        final isOwner =
            currentUserId != null && detail.ownerId == currentUserId;
        final datesEditability = tripDatesEditability(
          lifecycle: TripLifecycle.parse(detail.lifecycle),
          startDateIso: detail.startDate,
          now: DateTime.now(),
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.labels.settingsTitle),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => context.pop(),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (isOwner && datesEditability.any) ...[
                ..._buildDatesSection(detail, datesEditability),
                const SizedBox(height: 28),
              ],
              Text(
                widget.labels.budgetSectionTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (burnDown != null) ...[
                const SizedBox(height: 8),
                Text(
                  burnDown.isOverBudget
                      ? widget.labels.burnDownOver(detail.baseCurrency)
                      : widget.labels.burnDownRemaining(
                          burnDown.remainingCents,
                          detail.baseCurrency,
                        ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: burnDown.isOverBudget
                            ? AppColors.coralText
                            : AppColors.jadeTeal,
                      ),
                ),
              ],
              if (canManage) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<TripBudgetMode>(
                  initialValue: _mode,
                  decoration: InputDecoration(
                    labelText: widget.labels.budgetSectionTitle,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: TripBudgetMode.none,
                      child: Text(widget.labels.budgetModeNone),
                    ),
                    DropdownMenuItem(
                      value: TripBudgetMode.informational,
                      child: Text(widget.labels.budgetModeInformational),
                    ),
                    DropdownMenuItem(
                      value: TripBudgetMode.formal,
                      child: Text(widget.labels.budgetModeFormal),
                    ),
                  ],
                  onChanged: _savingBudget
                      ? null
                      : (v) => setState(() => _mode = v ?? TripBudgetMode.none),
                ),
                if (_mode.hasBurnDown) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _budgetAmountController,
                    decoration: InputDecoration(
                      labelText: widget.labels.budgetAmountLabel,
                      prefixText: _currencySymbol(detail.baseCurrency),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _savingBudget ? null : () => _saveBudget(detail),
                  child: _savingBudget
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.labels.saveBudget),
                ),
              ],
              const SizedBox(height: 28),
              Text(
                widget.labels.fxSectionTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                widget.labels.fxRateReadOnly,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.graphite,
                    ),
              ),
              const SizedBox(height: 12),
              fxRates.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (_, __) => const Text('Could not load FX rates'),
                data: (rows) => Column(
                  children: [
                    for (final row in rows) _fxTile(row, canManage),
                    if (canManage) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _capturingCurrency != null
                            ? null
                            : () => _pickAndCapture(detail, rows),
                        icon: const Icon(Icons.add),
                        label: Text(widget.labels.fxAddCurrency),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                widget.labels.subtripsSectionTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(widget.labels.subtripsToggleLabel),
                subtitle: Text(widget.labels.subtripsToggleBody),
                value: detail.subtripsEnabled,
                onChanged: canManage && !_savingSubtrips
                    ? (enabled) => _setSubtripsEnabled(enabled)
                    : null,
              ),
              const SizedBox(height: 28),
              ..._buildRetentionSection(),
            ],
          ),
        );
      },
    );
  }

  Widget _fxTile(TripFxRateRow row, bool canManage) {
    final labels = widget.labels;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  row.currency,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  row.rate.toStringAsFixed(4),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${labels.fxSource}: ${row.source}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.graphite,
                  ),
            ),
            Text(
              labels.fxCapturedAt(row.capturedAt.toUtc().toIso8601String()),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.graphite,
                  ),
            ),
            if (canManage) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: _capturingCurrency == row.currency
                      ? null
                      : () => _capture(row.currency),
                  child: _capturingCurrency == row.currency
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(labels.fxRefresh),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDatesSection(
    TripDetail detail,
    TripDatesEditability editability,
  ) {
    final labels = widget.labels;
    return [
      Text(
        labels.datesSectionTitle,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      _DateField(
        label: labels.startDateLabel,
        value: _startDate,
        enabled: editability.canEditStart && !_savingDates,
        onPick: editability.canEditStart ? _pickStartDate : null,
      ),
      if (!editability.canEditStart) ...[
        const SizedBox(height: 6),
        Text(
          labels.startDateLockedHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.graphite,
              ),
        ),
      ],
      const SizedBox(height: 12),
      _DateField(
        label: labels.endDateLabel,
        value: _endDate,
        enabled: editability.canEditEnd && !_savingDates,
        onPick: editability.canEditEnd ? _pickEndDate : null,
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
      FilledButton(
        onPressed: _savingDates ? null : () => _saveDates(detail),
        child: _savingDates
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(labels.saveDates),
      ),
    ];
  }

  List<Widget> _buildRetentionSection() {
    final labels = widget.labels;
    return [
      Text(
        labels.retentionSectionTitle,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        labels.offloadMediaBody,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.vamoColors.onSurfaceMuted,
            ),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: _offloadingMedia ? null : _confirmOffloadMedia,
          icon: _offloadingMedia
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_off_outlined),
          label: Text(labels.offloadMedia),
        ),
      ),
    ];
  }

  VamoDatePickerLabels get _datePickerLabels => VamoDatePickerLabels(
        cancel: widget.labels.datePickerCancel,
        skip: widget.labels.datePickerSkip,
        select: widget.labels.datePickerSelect,
      );

  Future<void> _pickStartDate() async {
    final result = await showVamoDatePicker(
      context: context,
      labels: _datePickerLabels,
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

  Future<void> _pickEndDate() async {
    final result = await showVamoDatePicker(
      context: context,
      labels: _datePickerLabels,
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

  void _validateDateRange() {
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      _dateRangeError = widget.labels.endBeforeStart;
    } else {
      _dateRangeError = null;
    }
  }

  Future<void> _saveDates(TripDetail detail) async {
    _validateDateRange();
    if (_dateRangeError != null) {
      setState(() {});
      return;
    }
    setState(() => _savingDates = true);
    try {
      await ref.read(tripsRepositoryProvider).updateTripDates(
            tripId: widget.tripId,
            startDate: _isoDate(_startDate),
            endDate: _isoDate(_endDate),
          );
    } catch (e) {
      if (mounted) {
        showActionError(
          context,
          ref,
          screen: 'trip_settings',
          action: 'update_trip_dates',
          error: e,
        );
      }
    } finally {
      if (mounted) setState(() => _savingDates = false);
    }
  }

  Future<void> _saveBudget(TripDetail detail) async {
    setState(() => _savingBudget = true);
    try {
      int? cents;
      if (_mode.hasBurnDown) {
        cents = parseAmountToCents(_budgetAmountController.text);
        if (cents == null || cents <= 0) return;
      }
      await ref.read(tripsRepositoryProvider).setTripBudget(
            tripId: widget.tripId,
            mode: _mode.name,
            budgetCents: cents,
          );
    } catch (e) {
      if (mounted) {
        showActionError(
          context,
          ref,
          screen: 'trip_settings',
          action: 'set_budget',
          error: e,
        );
      }
    } finally {
      if (mounted) setState(() => _savingBudget = false);
    }
  }

  Future<void> _confirmOffloadMedia() async {
    final labels = widget.labels;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(labels.offloadMediaConfirmTitle),
            content: Text(labels.offloadMediaConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(labels.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(labels.offloadMedia),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _offloadingMedia = true);
    try {
      final result = await ref
          .read(tripsRepositoryProvider)
          .offloadTripMediaCache(widget.tripId);
      final count =
          result.backgrounds + result.photos + result.videos + result.receipts;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count == 0
                  ? labels.offloadMediaNothing
                  : labels.offloadMediaSuccess(count),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showActionError(
          context,
          ref,
          screen: 'trip_settings',
          action: 'offload_media',
          error: e,
        );
      }
    } finally {
      if (mounted) setState(() => _offloadingMedia = false);
    }
  }

  Future<void> _setSubtripsEnabled(bool enabled) async {
    setState(() => _savingSubtrips = true);
    try {
      await ref.read(tripsRepositoryProvider).setSubtripsEnabled(
            tripId: widget.tripId,
            enabled: enabled,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.labels.subtripsSaveError)),
        );
      }
    } finally {
      if (mounted) setState(() => _savingSubtrips = false);
    }
  }

  Future<void> _capture(String currency) async {
    setState(() => _capturingCurrency = currency);
    try {
      await ref.read(tripsRepositoryProvider).captureFxRate(
            tripId: widget.tripId,
            currency: currency,
          );
    } catch (e) {
      if (mounted) {
        showActionError(
          context,
          ref,
          screen: 'trip_settings',
          action: 'capture_fx_rate',
          error: e,
        );
      }
    } finally {
      if (mounted) setState(() => _capturingCurrency = null);
    }
  }

  Future<void> _pickAndCapture(
    TripDetail detail,
    List<TripFxRateRow> existing,
  ) async {
    final captured = existing.map((r) => r.currency).toSet();
    final choices = _currencies
        .where((c) => c != detail.baseCurrency.toUpperCase())
        .where((c) => !captured.contains(c))
        .toList();
    if (choices.isEmpty) return;

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(widget.labels.fxAddCurrency),
        children: [
          for (final c in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c),
              child: Text(c),
            ),
        ],
      ),
    );
    if (picked != null) await _capture(picked);
  }

  String _currencySymbol(String code) {
    switch (code) {
      case 'EUR':
        return '€ ';
      case 'USD':
        return '\$ ';
      case 'GBP':
        return '£ ';
      default:
        return '$code ';
    }
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPick,
  });

  final String label;
  final DateTime? value;
  final bool enabled;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final formatted = value == null ? label : DateFormat.yMMMd().format(value!);
    return OutlinedButton(
      onPressed: enabled ? onPick : null,
      style: OutlinedButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        foregroundColor: colors.onSurface,
        side: BorderSide(color: colors.border),
      ),
      child: Text(value == null ? label : '$label: $formatted'),
    );
  }
}
