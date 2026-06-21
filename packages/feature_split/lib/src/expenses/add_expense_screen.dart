import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../trips/trips_providers.dart';
import 'expense_governance.dart';
import 'expense_governance_labels.dart';
import 'expense_models.dart';
import 'expense_consent_providers.dart';
import 'expenses_providers.dart';
import 'expenses_repository.dart';
import 'money_format.dart';
import 'ocr_suggestion_chip.dart';
import 'receipt_metadata.dart';
import 'receipt_ocr.dart';
import 'receipt_ocr_form_prefill.dart';
import '../places/places_repository.dart';
import 'add_expense_screen_labels.dart';
import 'expense_category_picker.dart';

/// Slice 2 + 6 — log a cost with optional non-base currency and FX snapshot.
class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({
    super.key,
    required this.tripId,
    this.mode = AddExpenseMode.committed,
    required this.labels,
    required this.screenLabels,
  });

  final String tripId;
  final AddExpenseMode mode;
  final ExpenseGovernanceLabels labels;
  final AddExpenseScreenLabels screenLabels;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  late final FlowTracker _flowTracker;

  static const _currencies = ['EUR', 'USD', 'GBP', 'CHF'];

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _baseOverrideController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _payerId;
  String _selectedCategoryKey = CategoryCatalog.other.key;
  String _expenseCurrency = 'EUR';
  bool _currencySyncedToTrip = false;
  String? _fxPreview;
  int? _autoBaseCents;
  String? _fxRateSource;
  bool _baseOverrideUserTouched = false;
  bool _previewLoading = false;
  bool _saving = false;
  final _picker = ImagePicker();
  String? _receiptSourcePath;
  ReceiptCaptureMetadata? _receiptMetadata;
  String? _placeLabel;
  String? _resolvedPlaceId;
  bool _ocrLoading = false;
  Future<void>? _pendingOcr;
  bool _ocrUsed = false;
  bool _currencyUserTouched = false;
  String? _amountError;
  final Set<OcrSuggestionField> _ocrSuggested = {};
  final Map<OcrSuggestionField, String> _ocrOriginal = {};

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
    _baseOverrideController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _refreshFxPreview(String tripBase) async {
    final expense = _expenseCurrency;
    if (expense == tripBase) {
      if (mounted) {
        setState(() {
          _fxPreview = null;
          _autoBaseCents = null;
          _baseOverrideController.clear();
        });
      }
      return;
    }
    final cents = parseAmountToCents(_amountController.text);
    if (cents == null || cents <= 0) {
      if (mounted) {
        setState(() {
          _fxPreview = null;
          _autoBaseCents = null;
        });
      }
      return;
    }
    setState(() => _previewLoading = true);
    try {
      final resolved = await ref
          .read(expensesRepositoryProvider)
          .resolveTripFxRateForExpense(
            tripId: widget.tripId,
            expenseCurrency: expense,
            tripBase: tripBase,
            amountCents: cents,
          );
      if (!mounted) return;
      setState(() {
        _autoBaseCents = resolved.baseCents;
        final amount = formatMoneyFromCents(resolved.baseCents, tripBase);
        _fxPreview = '≈ $amount in trip currency';
        if (!_baseOverrideUserTouched) {
          _baseOverrideController.text =
              (resolved.baseCents / 100).toStringAsFixed(2);
        }
        _previewLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fxPreview = 'Add this currency in trip settings first';
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
            body: Center(child: Text(widget.screenLabels.tripNotFound)),
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
            appBar: AppBar(title: Text(widget.screenLabels.title)),
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

            final labels = widget.labels;
            final splitLabel = labels.splitLabel(memberList.length);
            final isPropose = widget.mode == AddExpenseMode.proposed;
            final fxRows =
                ref.watch(tripFxRatesProvider(widget.tripId)).valueOrNull ?? [];
            final availableCurrencies = {
              tripBase.toUpperCase(),
              ...fxRows.map((r) => r.currency.toUpperCase()),
            }.toList()
              ..sort();

            if (isPropose) {
              final currentUserId = ref.watch(currentUserProvider)?.id;
              final role = ref.watch(
                currentMemberRoleProvider(
                  (tripId: widget.tripId, userId: currentUserId),
                ),
              );
              final tripReadOnly =
                  isTripReadOnly(TripLifecycle.parse(detail.lifecycle));
              if (!canShowProposeExpenseForm(
                tripReadOnly: tripReadOnly,
                memberRole: role,
              )) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppRoutes.trip(widget.tripId));
                  }
                });
                return const Scaffold(body: SizedBox.shrink());
              }
            }

            final inForeignCurrency = _expenseCurrency != tripBase;
            final screenTitle =
                isPropose ? labels.proposeCostTitle : labels.addExpenseTitle;
            final saveLabel =
                isPropose ? labels.saveProposal : labels.saveExpense;

            return Scaffold(
              appBar: AppBar(
                title: Text(screenTitle),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _saving ? null : () => context.pop(),
                ),
              ),
              bottomNavigationBar: SafeArea(
                minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.goLime,
                    foregroundColor: AppColors.ink,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: (_saving || _ocrLoading)
                      ? null
                      : () => _save(tripBaseCurrency: tripBase),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_ctaLabel(saveLabel, tripBase)),
                ),
              ),
              body: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 28),
                  children: [
                    Text(
                      detail.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.ink,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels.tripBalancesIn(tripBase),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.graphite),
                    ),
                    const SizedBox(height: 16),
                    _AmountEntryPanel(
                      amountText: _amountController.text,
                      currency: _expenseCurrency,
                      currencySymbol: _currencySymbol(_expenseCurrency),
                      errorText: _amountError,
                      onDigit: (value) => _appendAmountToken(value, tripBase),
                      onDecimal: () => _appendAmountToken('.', tripBase),
                      onBackspace: () => _backspaceAmount(tripBase),
                    ),
                    if (_ocrSuggested.contains(OcrSuggestionField.amount) &&
                        !isPropose)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(top: 8),
                        child: OcrSuggestionChip(),
                      ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _expenseCurrency,
                      decoration: const InputDecoration(
                        labelText: 'Currency',
                      ),
                      items: availableCurrencies
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
                              setState(() {
                                _expenseCurrency = v;
                                _currencyUserTouched = true;
                                _onUserEdited(OcrSuggestionField.currency);
                              });
                              _refreshFxPreview(tripBase);
                            },
                    ),
                    if (_ocrSuggested.contains(OcrSuggestionField.currency) &&
                        !isPropose)
                      const OcrSuggestionChip(),
                    const SizedBox(height: 16),
                    if (inForeignCurrency) ...[
                      if (_previewLoading)
                        const LinearProgressIndicator(minHeight: 2)
                      else if (_fxPreview != null)
                        Text(
                          _fxPreview!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.jadeTeal),
                        ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _baseOverrideController,
                        decoration: InputDecoration(
                          labelText:
                              widget.labels.convertedAmountLabel(tripBase),
                          prefixText: _currencySymbol(tripBase),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[\d.,]'),
                          ),
                        ],
                        onChanged: (_) {
                          _baseOverrideUserTouched = true;
                          _fxRateSource = 'manual';
                        },
                        validator: (v) {
                          if (!inForeignCurrency) return null;
                          if (parseAmountToCents(v ?? '') == null) {
                            return 'Enter a valid converted amount';
                          }
                          return null;
                        },
                      ),
                      if (_fxRateSource == 'receipt')
                        Text(
                          widget.labels.fxSourceReceipt,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.graphite),
                        ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'Dinner',
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => _onUserEdited(OcrSuggestionField.title),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Add a short description';
                        }
                        return null;
                      },
                    ),
                    if (_ocrSuggested.contains(OcrSuggestionField.title) &&
                        !isPropose)
                      const OcrSuggestionChip(),
                    const SizedBox(height: 16),
                    ExpenseCategoryPicker(
                      selectedKey: _selectedCategoryKey,
                      enabled: !_saving,
                      onChanged: (key) =>
                          setState(() => _selectedCategoryKey = key),
                    ),
                    if (!isPropose) ...[
                      if (_placeLabel != null && _placeLabel!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Place',
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.place_outlined,
                                size: 18,
                                color: AppColors.graphite,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _placeLabel!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: AppColors.graphite),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_ocrSuggested
                            .contains(OcrSuggestionField.placeLabel))
                          const OcrSuggestionChip(),
                      ],
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed:
                            (_saving || _ocrLoading) ? null : _pickReceipt,
                        icon: const Icon(Icons.document_scanner_outlined),
                        label: Text(widget.screenLabels.scanReceipt),
                      ),
                      if (_ocrLoading) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(minHeight: 2),
                        Padding(
                          padding: const EdgeInsetsDirectional.only(top: 8),
                          child: Text(
                            'Reading receipt…',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.graphite),
                          ),
                        ),
                      ],
                      if (_receiptSourcePath != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(_receiptSourcePath!),
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Receipt attached (optional evidence)',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.graphite),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove receipt',
                              onPressed: (_saving || _ocrLoading)
                                  ? null
                                  : () => setState(() {
                                        _receiptSourcePath = null;
                                        _receiptMetadata = null;
                                        _placeLabel = null;
                                        _resolvedPlaceId = null;
                                        _ocrSuggested.clear();
                                        _ocrOriginal.clear();
                                        _ocrUsed = false;
                                      }),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ],
                    ],
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
                      onChanged:
                          _saving ? null : (v) => setState(() => _payerId = v),
                    ),
                    const SizedBox(height: 16),
                    _SplitPreviewCard(
                      splitLabel: splitLabel,
                      members: memberList.map((m) => m.displayName).toList(),
                      amountPreview: _splitAmountPreview(
                        tripBase: tripBase,
                        memberCount: memberList.length,
                      ),
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

  void _setAmountText(String value, String tripBase) {
    _amountController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _onUserEdited(OcrSuggestionField.amount);
    setState(() => _amountError = null);
    _refreshFxPreview(tripBase);
  }

  void _appendAmountToken(String token, String tripBase) {
    final current = _amountController.text;
    var next = current;
    if (token == '.') {
      if (current.contains('.')) return;
      next = current.isEmpty ? '0.' : '$current.';
    } else {
      final decimalIndex = current.indexOf('.');
      if (decimalIndex >= 0 &&
          current.length - decimalIndex > 2 &&
          token != 'backspace') {
        return;
      }
      next = current == '0' ? token : '$current$token';
    }
    _setAmountText(next, tripBase);
  }

  void _backspaceAmount(String tripBase) {
    final current = _amountController.text;
    if (current.isEmpty) return;
    _setAmountText(current.substring(0, current.length - 1), tripBase);
  }

  String _ctaLabel(String saveLabel, String tripBase) {
    final cents = parseAmountToCents(_amountController.text);
    if (cents == null || cents <= 0) return saveLabel;
    final currency = _expenseCurrency.toUpperCase() == tripBase.toUpperCase()
        ? tripBase
        : _expenseCurrency;
    return '$saveLabel · ${formatMoneyFromCents(cents, currency)}';
  }

  String? _splitAmountPreview({
    required String tripBase,
    required int memberCount,
  }) {
    if (memberCount <= 0) return null;
    final cents = parseAmountToCents(_amountController.text);
    if (cents == null || cents <= 0) return null;
    final baseCents = _expenseCurrency.toUpperCase() == tripBase.toUpperCase()
        ? cents
        : parseAmountToCents(_baseOverrideController.text) ?? _autoBaseCents;
    if (baseCents == null) return null;
    return formatMoneyFromCents((baseCents / memberCount).round(), tripBase);
  }

  Future<void> _pickReceipt() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(widget.screenLabels.takePhoto),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(widget.screenLabels.chooseGallery),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final metadata = await resolveReceiptMetadata(picked.path);
    if (!mounted) return;
    setState(() {
      _receiptSourcePath = picked.path;
      _receiptMetadata = metadata;
      _placeLabel = null;
      _resolvedPlaceId = null;
      _ocrSuggested.clear();
      _ocrOriginal.clear();
      _ocrUsed = false;
      _currencyUserTouched = false;
    });

    if (receiptOcrSupported) {
      _pendingOcr = _runReceiptOcr(picked.path);
      await _pendingOcr;
    }
  }

  Future<void> _runReceiptOcr(String path) async {
    setState(() => _ocrLoading = true);
    try {
      final suggestion = await scanReceiptImage(path);
      if (!mounted || suggestion == null || !suggestion.hasAnySuggestion) {
        return;
      }
      _applyOcrSuggestion(
        suggestion,
        tripBase: ref
                .read(tripDetailProvider(widget.tripId))
                .valueOrNull
                ?.baseCurrency ??
            'EUR',
      );
      await _resolvePlaceFromReceipt(suggestion);
    } catch (e, stackTrace) {
      if (!mounted) return;
      reportAndLog(
        e,
        stackTrace,
        screen: 'add_expense',
        action: 'ocr_scan',
        analytics: ref.read(analyticsProvider),
      );
    } finally {
      if (mounted) {
        setState(() {
          _ocrLoading = false;
          _pendingOcr = null;
        });
      }
    }
  }

  Future<void> _resolvePlaceFromReceipt(ReceiptParseResult suggestion) async {
    if (!placeResolutionSupported) return;
    final result = await ref.read(placesRepositoryProvider).resolveFromReceipt(
          tripId: widget.tripId,
          parse: suggestion,
          exif: _receiptMetadata,
        );
    if (!mounted) return;
    if (result.placeId != null) {
      setState(() => _resolvedPlaceId = result.placeId);
    }
  }

  void _applyOcrSuggestion(
    ReceiptParseResult suggestion, {
    required String tripBase,
  }) {
    final prefill = applyReceiptOcrPrefill(
      suggestion: suggestion,
      supportedCurrencies: _currencies,
      currencyUserTouched: _currencyUserTouched,
      currentDescription: _descriptionController.text,
    );
    if (!prefill.ocrUsed) return;

    setState(() {
      _ocrUsed = true;
      if (prefill.amountText != null) {
        _amountController.text = prefill.amountText!;
        _ocrSuggested.add(OcrSuggestionField.amount);
        _ocrOriginal[OcrSuggestionField.amount] = prefill.amountText!;
      }
      if (prefill.currency != null) {
        _expenseCurrency = prefill.currency!;
        _ocrSuggested.add(OcrSuggestionField.currency);
        _ocrOriginal[OcrSuggestionField.currency] = prefill.currency!;
      }
      if (prefill.description != null) {
        _descriptionController.text = prefill.description!;
        _ocrSuggested.add(OcrSuggestionField.title);
        _ocrOriginal[OcrSuggestionField.title] = prefill.description!;
      }
      if (prefill.placeLabel != null) {
        _placeLabel = prefill.placeLabel;
        _ocrSuggested.add(OcrSuggestionField.placeLabel);
        _ocrOriginal[OcrSuggestionField.placeLabel] = prefill.placeLabel!;
      }
      if (suggestion.hasReceiptFxHint &&
          suggestion.printedBaseCurrency!.toUpperCase() ==
              tripBase.toUpperCase() &&
          suggestion.printedBaseCents != null) {
        _baseOverrideController.text =
            (suggestion.printedBaseCents! / 100).toStringAsFixed(2);
        _baseOverrideUserTouched = false;
        _fxRateSource = 'receipt';
      }
    });
  }

  void _onUserEdited(OcrSuggestionField field) {
    if (!_ocrSuggested.contains(field)) return;
    final original = _ocrOriginal[field];
    if (original == null) return;

    final changed = switch (field) {
      OcrSuggestionField.amount => _amountController.text.trim() != original,
      OcrSuggestionField.currency => _expenseCurrency != original,
      OcrSuggestionField.title =>
        _descriptionController.text.trim() != original,
      OcrSuggestionField.placeLabel => _placeLabel != original,
    };

    if (changed) {
      ref.read(analyticsProvider).capture(
        VamoEvent.ocrSuggestionEdited,
        properties: {'field': field.name},
      );
      setState(() => _ocrSuggested.remove(field));
    }
  }

  Future<void> _save({required String tripBaseCurrency}) async {
    if (_pendingOcr != null) await _pendingOcr;
    if (!_formKey.currentState!.validate()) return;
    final payerId = _payerId;
    if (payerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.screenLabels.choosePayer)),
      );
      return;
    }

    final cents = parseAmountToCents(_amountController.text);
    if (cents == null || cents <= 0) {
      setState(() => _amountError = 'Enter a valid amount');
      return;
    }

    final inForeignCurrency =
        _expenseCurrency.toUpperCase() != tripBaseCurrency.toUpperCase();
    final manualBaseCents = inForeignCurrency
        ? parseAmountToCents(_baseOverrideController.text)
        : null;
    final useManualBase = manualBaseCents != null &&
        (_baseOverrideUserTouched ||
            _fxRateSource == 'receipt' ||
            (_autoBaseCents != null && manualBaseCents != _autoBaseCents));

    setState(() => _saving = true);
    try {
      double fxRate = 1.0;
      var baseCents = cents;
      if (inForeignCurrency) {
        final resolved = await ref
            .read(expensesRepositoryProvider)
            .resolveTripFxRateForExpense(
              tripId: widget.tripId,
              expenseCurrency: _expenseCurrency,
              tripBase: tripBaseCurrency,
              amountCents: cents,
            );
        fxRate = resolved.fxRate;
        if (useManualBase) {
          baseCents = manualBaseCents;
          fxRate = fxRateFromReceiptTotals(
            amountCents: cents,
            receiptBaseCents: baseCents,
          );
        } else {
          baseCents = resolved.baseCents;
        }
      }

      if (widget.mode == AddExpenseMode.proposed) {
        await ref.read(expensesRepositoryProvider).proposeExpense(
              tripId: widget.tripId,
              payerId: payerId,
              description: _descriptionController.text,
              amountCents: cents,
              currency: _expenseCurrency,
              baseCents: baseCents,
              fxRate: fxRate,
              category: _selectedCategoryKey,
              manualBaseCents: useManualBase ? baseCents : null,
              fxRateSource: useManualBase ? (_fxRateSource ?? 'manual') : null,
              lockConversion: useManualBase,
            );
      } else {
        await ref.read(expensesRepositoryProvider).addExpense(
              input: AddExpenseInput(
                tripId: widget.tripId,
                description: _descriptionController.text,
                amountCents: cents,
                expenseCurrency: _expenseCurrency,
                payerId: payerId,
                category: _selectedCategoryKey,
                receiptSourcePath: _receiptSourcePath,
                capturedLat: _receiptMetadata?.lat,
                capturedLng: _receiptMetadata?.lng,
                capturedAt: _receiptMetadata?.capturedAt,
                placeLabel: _placeLabel,
                placeId: _resolvedPlaceId,
                ocrUsed: _ocrUsed,
                manualBaseCents: useManualBase ? baseCents : null,
                fxRateSource:
                    useManualBase ? (_fxRateSource ?? 'manual') : null,
                lockConversion: useManualBase,
              ),
              baseCurrency: tripBaseCurrency,
            );
      }
      if (!mounted) return;
      _flowTracker.complete();
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'add_expense',
        action: widget.mode == AddExpenseMode.proposed
            ? 'propose_expense'
            : 'add_expense',
        error: e,
      );
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.trip(widget.tripId));
      }
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

class _AmountEntryPanel extends StatelessWidget {
  const _AmountEntryPanel({
    required this.amountText,
    required this.currency,
    required this.currencySymbol,
    required this.errorText,
    required this.onDigit,
    required this.onDecimal,
    required this.onBackspace,
  });

  final String amountText;
  final String currency;
  final String currencySymbol;
  final String? errorText;
  final ValueChanged<String> onDigit;
  final VoidCallback onDecimal;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = amountText.trim().isEmpty ? '0.00' : amountText;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.jadeTeal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: errorText == null
              ? AppColors.jadeTeal.withValues(alpha: 0.24)
              : theme.colorScheme.error,
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FittedBox(
                    alignment: AlignmentDirectional.centerStart,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$currencySymbol$display',
                      maxLines: 1,
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(currency),
                ),
              ],
            ),
            if (errorText != null) ...[
              const SizedBox(height: 6),
              Text(
                errorText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            _AmountKeypad(
              onDigit: onDigit,
              onDecimal: onDecimal,
              onBackspace: onBackspace,
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountKeypad extends StatelessWidget {
  const _AmountKeypad({
    required this.onDigit,
    required this.onDecimal,
    required this.onBackspace,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDecimal;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', 'backspace'],
    ];

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 2),
            child: Row(
              children: [
                for (final key in row)
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsetsDirectional.symmetric(horizontal: 2),
                      child: _AmountKey(
                        value: key,
                        onTap: switch (key) {
                          '.' => onDecimal,
                          'backspace' => onBackspace,
                          _ => () => onDigit(key),
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AmountKey extends StatelessWidget {
  const _AmountKey({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isBackspace = value == 'backspace';
    return SizedBox(
      height: 42,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: isBackspace
            ? const Icon(Icons.backspace_outlined, size: 20)
            : Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
      ),
    );
  }
}

class _SplitPreviewCard extends StatelessWidget {
  const _SplitPreviewCard({
    required this.splitLabel,
    required this.members,
    required this.amountPreview,
  });

  final String splitLabel;
  final List<String> members;
  final String? amountPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Split',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.graphite,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: -4,
                    children: [
                      for (final name in members.take(5))
                        CircleAvatar(
                          radius: 14,
                          backgroundColor:
                              AppColors.jadeTeal.withValues(alpha: 0.16),
                          child: Text(
                            _initial(name),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    amountPreview == null
                        ? splitLabel
                        : '$splitLabel · $amountPreview each',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.lock_outline, color: AppColors.graphite, size: 20),
          ],
        ),
      ),
    );
  }

  static String _initial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}
