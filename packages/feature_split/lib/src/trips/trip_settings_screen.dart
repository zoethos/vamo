import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

        final readOnly = isTripReadOnly(TripLifecycle.parse(detail.lifecycle));
        final canManage = canManageTripBudgetAndFx(
          tripReadOnly: readOnly,
          memberRole: role,
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
