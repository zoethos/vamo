import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'expense_models.dart';
import 'expenses_providers.dart';
import 'expenses_repository.dart';
import 'money_format.dart';
import '../trips/trips_providers.dart';

/// Slice 2 + 6 — log a cost with optional non-base currency and FX snapshot.
class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  late final FlowTracker _flowTracker;

  static const _currencies = ['EUR', 'USD', 'GBP', 'CHF'];

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _payerId;
  String _expenseCurrency = 'EUR';
  bool _currencySyncedToTrip = false;
  String? _fxPreview;
  bool _previewLoading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _flowTracker = FlowTracker(
      flow: 'add_expense',
      analytics: ref.read(analyticsProvider),
    );
  }

  @override
  void dispose() {
    _flowTracker.abandonIfIncomplete();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _refreshFxPreview(String tripBase) async {
    final expense = _expenseCurrency;
    if (expense == tripBase) {
      if (mounted) setState(() => _fxPreview = null);
      return;
    }
    final cents = parseAmountToCents(_amountController.text);
    if (cents == null || cents <= 0) {
      if (mounted) setState(() => _fxPreview = null);
      return;
    }
    setState(() => _previewLoading = true);
    try {
      final snapshot =
          await ref.read(fxRatesClientProvider).fetchForBase(tripBase);
      final baseCents = snapshot.toBaseCents(
        amountCents: cents,
        expenseCurrency: expense,
      );
      if (!mounted) return;
      setState(() {
        final amount =
            formatMoneyFromCents(baseCents, tripBase);
        _fxPreview = snapshot.isStale
            ? '≈ $amount (rate may be stale)'
            : '≈ $amount in trip currency';
        _previewLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fxPreview = 'Could not load FX rate';
        _previewLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(tripDetailProvider(widget.tripId));
    final members = ref.watch(tripMembersForExpenseProvider(widget.tripId));

    return trip.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: AppErrorState(
          screen: 'add_expense',
          message: formatActionFailureMessage(e),
          kind: classifyActionFailureKind(e),
          onRetry: () => ref.invalidate(tripDetailProvider(widget.tripId)),
        ),
      ),
      data: (detail) {
        if (detail == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Trip not found')),
          );
        }

        final tripBase = detail.baseCurrency;
        if (!_currencySyncedToTrip) {
          _currencySyncedToTrip = true;
          _expenseCurrency = tripBase;
        }

        return members.when(
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Scaffold(
            appBar: AppBar(title: const Text('Add expense')),
            body: AppErrorState(
              screen: 'add_expense',
              message: formatActionFailureMessage(e),
              kind: classifyActionFailureKind(e),
              onRetry: () =>
                  ref.invalidate(tripMembersForExpenseProvider(widget.tripId)),
            ),
          ),
          data: (memberList) {
            if (_payerId == null && memberList.isNotEmpty) {
              _payerId = memberList.first.userId;
            }

            final splitLabel = memberList.length == 1
                ? 'All on you (solo)'
                : 'Split equally · ${memberList.length} Vamigos';

            final inForeignCurrency = _expenseCurrency != tripBase;

            return Scaffold(
              appBar: AppBar(
                title: const Text('Add expense'),
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
                      detail.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.tealDark,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Trip balances in $tripBase',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: _expenseCurrency,
                      decoration: const InputDecoration(
                        labelText: 'Spent in',
                      ),
                      items: _currencies
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(c),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() => _expenseCurrency = v);
                              _refreshFxPreview(tripBase);
                            },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _amountController,
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        prefixText: _currencySymbol(_expenseCurrency),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[\d.,]'),
                        ),
                      ],
                      onChanged: (_) => _refreshFxPreview(tripBase),
                      validator: (v) {
                        if (parseAmountToCents(v ?? '') == null) {
                          return 'Enter a valid amount';
                        }
                        return null;
                      },
                    ),
                    if (inForeignCurrency) ...[
                      const SizedBox(height: 8),
                      if (_previewLoading)
                        const LinearProgressIndicator(minHeight: 2)
                      else if (_fxPreview != null)
                        Text(
                          _fxPreview!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.teal),
                        ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'Dinner',
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Add a short description';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _payerId,
                      decoration: const InputDecoration(labelText: 'Who paid?'),
                      items: memberList
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.userId,
                              child: Text(m.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _payerId = v),
                    ),
                    const SizedBox(height: 16),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Split',
                      ),
                      child: Text(
                        splitLabel,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: _saving
                          ? null
                          : () => _save(
                                tripBaseCurrency: tripBase,
                              ),
                      child: _saving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save expense'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _save({required String tripBaseCurrency}) async {
    if (!_formKey.currentState!.validate()) return;
    final payerId = _payerId;
    if (payerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose who paid.')),
      );
      return;
    }

    final cents = parseAmountToCents(_amountController.text);
    if (cents == null) return;

    setState(() => _saving = true);
    try {
      await ref.read(expensesRepositoryProvider).addExpense(
            input: AddExpenseInput(
              tripId: widget.tripId,
              description: _descriptionController.text,
              amountCents: cents,
              expenseCurrency: _expenseCurrency,
              payerId: payerId,
            ),
            baseCurrency: tripBaseCurrency,
          );
      if (!mounted) return;
      _flowTracker.complete();
      context.pop();
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'add_expense',
        action: 'add_expense',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _currencySymbol(String code) {
    switch (code) {
      case 'EUR':
        return '€ ';
      case 'USD':
        return r'$ ';
      case 'GBP':
        return '£ ';
      default:
        return '$code ';
    }
  }
}
