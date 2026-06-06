import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

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
import '../trips/trips_providers.dart';

/// Slice 2 + 6 — log a cost with optional non-base currency and FX snapshot.
class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({
    super.key,
    required this.tripId,
    this.mode = AddExpenseMode.committed,
    required this.labels,
  });

  final String tripId;
  final AddExpenseMode mode;
  final ExpenseGovernanceLabels labels;

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
  final _picker = ImagePicker();
  String? _receiptSourcePath;
  ReceiptCaptureMetadata? _receiptMetadata;
  String? _placeLabel;
  String? _resolvedPlaceId;
  bool _ocrLoading = false;
  Future<void>? _pendingOcr;
  bool _ocrUsed = false;
  bool _currencyUserTouched = false;
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

            final labels = widget.labels;
            final splitLabel = labels.splitLabel(memberList.length);
            final isPropose = widget.mode == AddExpenseMode.proposed;

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
              body: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
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
                      onChanged: (_) {
                        _onUserEdited(OcrSuggestionField.amount);
                        _refreshFxPreview(tripBase);
                      },
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
                              ?.copyWith(color: AppColors.jadeTeal),
                        ),
                    ],
                    if (_ocrSuggested.contains(OcrSuggestionField.amount) &&
                        !isPropose)
                      const OcrSuggestionChip(),
                    const SizedBox(height: 16),
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
                        label: const Text('Scan receipt'),
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
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton(
                        onPressed: (_saving || _ocrLoading)
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
                            : Text(saveLabel),
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

  Future<void> _pickReceipt() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
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
      _applyOcrSuggestion(suggestion);
      await _resolvePlaceFromReceipt(suggestion);
    } catch (e) {
      if (!mounted) return;
      ref.read(analyticsProvider).reportActionFailed(
            screen: 'add_expense',
            action: 'ocr_scan',
            error: e,
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

  void _applyOcrSuggestion(ReceiptParseResult suggestion) {
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
    });
  }

  void _onUserEdited(OcrSuggestionField field) {
    if (!_ocrSuggested.contains(field)) return;
    final original = _ocrOriginal[field];
    if (original == null) return;

    final changed = switch (field) {
      OcrSuggestionField.amount =>
        _amountController.text.trim() != original,
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
        const SnackBar(content: Text('Choose who paid.')),
      );
      return;
    }

    final cents = parseAmountToCents(_amountController.text);
    if (cents == null) return;

    setState(() => _saving = true);
    try {
      double fxRate = 1.0;
      var baseCents = cents;
      if (_expenseCurrency.toUpperCase() != tripBaseCurrency.toUpperCase()) {
        final snapshot =
            await ref.read(fxRatesClientProvider).fetchForBase(tripBaseCurrency);
        fxRate = snapshot.rateExpenseToBase(_expenseCurrency);
        baseCents = snapshot.toBaseCents(
          amountCents: cents,
          expenseCurrency: _expenseCurrency,
        );
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
            );
      } else {
        await ref.read(expensesRepositoryProvider).addExpense(
              input: AddExpenseInput(
                tripId: widget.tripId,
                description: _descriptionController.text,
                amountCents: cents,
                expenseCurrency: _expenseCurrency,
                payerId: payerId,
                receiptSourcePath: _receiptSourcePath,
                capturedLat: _receiptMetadata?.lat,
                capturedLng: _receiptMetadata?.lng,
                capturedAt: _receiptMetadata?.capturedAt,
                placeLabel: _placeLabel,
                placeId: _resolvedPlaceId,
                ocrUsed: _ocrUsed,
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
