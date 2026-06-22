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

const _ink = AppColors.ink;
const _graphite = AppColors.graphite;
const _mist = AppColors.mistGray;
const _cream = AppColors.cream;
const _jade = AppColors.jadeTeal;
const _coral = AppColors.sunsetCoral;

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
  bool _categoryUserTouched = false;
  bool _categorySyncedFromTrip = false;
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
            final currentUserId = ref.watch(currentUserProvider)?.id;
            if (_payerId == null && memberList.isNotEmpty) {
              if (currentUserId != null &&
                  memberList.any((m) => m.userId == currentUserId)) {
                _payerId = currentUserId;
              } else {
                _payerId = memberList.first.userId;
              }
            }

            final tripExpenses =
                ref.watch(tripExpensesProvider(widget.tripId)).valueOrNull ??
                    const <ExpenseSummary>[];
            if (!_categoryUserTouched && !_categorySyncedFromTrip) {
              _categorySyncedFromTrip = true;
              final lastCategory = _lastExpenseCategory(tripExpenses);
              if (lastCategory != null) {
                _selectedCategoryKey = lastCategory;
              }
            }

            final labels = widget.labels;
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
            final shareCents = _shareCentsPerMember(
              tripBase: tripBase,
              memberCount: memberList.length,
            );
            final sharePreview = shareCents == null
                ? null
                : formatMoneyFromCents(shareCents, tripBase);
            final screenLabels = widget.screenLabels;
            final categoryEntry = CategoryCatalog.resolve(_selectedCategoryKey);

            return Scaffold(
              appBar: AppBar(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(screenTitle),
                    Text(
                      detail.name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _graphite,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _saving ? null : () => context.pop(),
                ),
              ),
              bottomNavigationBar: SafeArea(
                minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: FilledButton(
                  key: const Key('addExpensePinnedCta'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.goLime,
                    foregroundColor: _ink,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView(
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 12),
                        children: [
                          _AmountDisplay(
                            amountText: _amountController.text,
                            currencySymbol:
                                _currencySymbol(_expenseCurrency).trim(),
                            errorText: _amountError,
                          ),
                          if (_ocrSuggested
                                  .contains(OcrSuggestionField.amount) &&
                              !isPropose)
                            const Padding(
                              padding: EdgeInsetsDirectional.only(top: 8),
                              child: OcrSuggestionChip(),
                            ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: _CurrencyPill(
                              currency: _expenseCurrency,
                              enabled: !_saving,
                              onTap: () => _showCurrencySheet(
                                tripBase: tripBase,
                                currencies: availableCurrencies,
                              ),
                            ),
                          ),
                          if (_ocrSuggested
                                  .contains(OcrSuggestionField.currency) &&
                              !isPropose)
                            const Padding(
                              padding: EdgeInsetsDirectional.only(top: 8),
                              child: OcrSuggestionChip(),
                            ),
                          if (inForeignCurrency) ...[
                            const SizedBox(height: 10),
                            _FxSummaryRow(
                              preview: _fxPreview,
                              loading: _previewLoading,
                              tripBase: tripBase,
                              baseOverrideController: _baseOverrideController,
                              currencySymbol: _currencySymbol(tripBase).trim(),
                              convertedAmountLabel:
                                  widget.labels.convertedAmountLabel(tripBase),
                              fxSourceReceipt: widget.labels.fxSourceReceipt,
                              fxRateSource: _fxRateSource,
                              enabled: !_saving,
                              onTap: () => _showFxSheet(
                                tripBase: tripBase,
                                inForeignCurrency: inForeignCurrency,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _EssentialChip(
                                key: const Key('addExpensePayerChip'),
                                icon: Icons.person_outline,
                                iconColor: _coral,
                                label: _payerChipLabel(
                                  memberList,
                                  currentUserId: currentUserId,
                                ),
                                enabled: !_saving,
                                onTap: () => _showPayerSheet(memberList),
                              ),
                              _EssentialChip(
                                key: const Key('addExpenseCategoryChip'),
                                icon: categoryEntry.icon,
                                iconColor: categoryEntry.color,
                                label: categoryEntry.label,
                                enabled: !_saving,
                                onTap: () => _showCategorySheet(),
                              ),
                              if (!isPropose)
                                _EssentialChip(
                                  icon: Icons.document_scanner_outlined,
                                  iconColor: _graphite,
                                  label: _receiptSourcePath == null
                                      ? screenLabels.attachReceipt
                                      : screenLabels.receiptAttached,
                                  enabled: !_saving && !_ocrLoading,
                                  onTap: _receiptSourcePath == null
                                      ? _pickReceipt
                                      : _showReceiptSheet,
                                ),
                              if (!isPropose &&
                                  (_placeLabel != null &&
                                      _placeLabel!.isNotEmpty))
                                _EssentialChip(
                                  icon: Icons.place_outlined,
                                  iconColor: _graphite,
                                  label: _placeLabel!,
                                  enabled: !_saving,
                                  onTap: _showPlaceSheet,
                                )
                              else if (!isPropose)
                                _EssentialChip(
                                  icon: Icons.place_outlined,
                                  iconColor: _graphite,
                                  label: screenLabels.addPlace,
                                  enabled: !_saving,
                                  onTap: _showPlaceSheet,
                                ),
                              _EssentialChip(
                                icon: Icons.notes_outlined,
                                iconColor: _graphite,
                                label:
                                    _descriptionController.text.trim().isEmpty
                                        ? screenLabels.addNote
                                        : _descriptionController.text.trim(),
                                enabled: !_saving,
                                onTap: _showDescriptionSheet,
                              ),
                            ],
                          ),
                          if (_ocrSuggested
                                  .contains(OcrSuggestionField.title) &&
                              !isPropose)
                            const Padding(
                              padding: EdgeInsetsDirectional.only(top: 8),
                              child: OcrSuggestionChip(),
                            ),
                          if (_ocrSuggested
                                  .contains(OcrSuggestionField.placeLabel) &&
                              !isPropose)
                            const Padding(
                              padding: EdgeInsetsDirectional.only(top: 8),
                              child: OcrSuggestionChip(),
                            ),
                          if (_ocrLoading) ...[
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(minHeight: 2),
                            Padding(
                              padding: const EdgeInsetsDirectional.only(top: 8),
                              child: Text(
                                screenLabels.readingReceipt,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: _graphite),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          _SplitControl(
                            labels: screenLabels,
                            governanceLabels: labels,
                            members: memberList,
                            sharePreview: sharePreview,
                            memberCount: memberList.length,
                            onCustomTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    screenLabels.customSplitComingSoon,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
                      child: _AmountKeypad(
                        onDigit: (value) => _appendAmountToken(value, tripBase),
                        onDecimal: () => _appendAmountToken('.', tripBase),
                        onBackspace: () => _backspaceAmount(tripBase),
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

  String? _lastExpenseCategory(List<ExpenseSummary> expenses) {
    if (expenses.isEmpty) return null;
    final sorted = [...expenses]
      ..sort((a, b) => b.spentAt.compareTo(a.spentAt));
    for (final expense in sorted) {
      final category = expense.category;
      if (category != null && category.trim().isNotEmpty) {
        return CategoryCatalog.resolve(category).key;
      }
    }
    return null;
  }

  String _payerChipLabel(
    List<TripMemberView> members, {
    required String? currentUserId,
  }) {
    final payerId = _payerId;
    if (payerId == null) return widget.screenLabels.choosePayer;
    if (payerId == currentUserId) return widget.screenLabels.youPaid;
    for (final member in members) {
      if (member.userId == payerId) {
        return widget.screenLabels.paidBy(member.displayName);
      }
    }
    return widget.screenLabels.choosePayer;
  }

  String _effectiveDescription() {
    final text = _descriptionController.text.trim();
    if (text.isNotEmpty) return text;
    return CategoryCatalog.resolve(_selectedCategoryKey).label;
  }

  void _showCurrencySheet({
    required String tripBase,
    required List<String> currencies,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    widget.screenLabels.currencySheetTitle,
                    style:
                        Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                              color: _ink,
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                ),
              ),
              for (final code in currencies)
                ListTile(
                  key: Key('addExpenseCurrencyOption_$code'),
                  title: Text(code),
                  trailing: _expenseCurrency == code
                      ? const Icon(Icons.check, color: _ink)
                      : null,
                  onTap: _saving
                      ? null
                      : () {
                          Navigator.of(sheetContext).pop();
                          setState(() {
                            _expenseCurrency = code;
                            _currencyUserTouched = true;
                            _onUserEdited(OcrSuggestionField.currency);
                          });
                          _refreshFxPreview(tripBase);
                        },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showPayerSheet(List<TripMemberView> members) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    widget.screenLabels.payerSheetTitle,
                    style:
                        Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                              color: _ink,
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                ),
              ),
              for (final member in members)
                ListTile(
                  key: Key('addExpensePayerOption_${member.userId}'),
                  title: Text(member.displayName),
                  trailing: _payerId == member.userId
                      ? const Icon(Icons.check, color: _ink)
                      : null,
                  onTap: _saving
                      ? null
                      : () {
                          Navigator.of(sheetContext).pop();
                          setState(() => _payerId = member.userId);
                        },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showCategorySheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      widget.screenLabels.categorySheetTitle,
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            color: _ink,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
                for (final entry in CategoryCatalog.canonical)
                  ListTile(
                    key: Key('addExpenseCategoryOption_${entry.key}'),
                    leading: Icon(entry.icon, color: entry.color),
                    title: Text(entry.label),
                    trailing: _selectedCategoryKey == entry.key
                        ? const Icon(Icons.check, color: _ink)
                        : null,
                    onTap: _saving
                        ? null
                        : () {
                            Navigator.of(sheetContext).pop();
                            setState(() {
                              _selectedCategoryKey = entry.key;
                              _categoryUserTouched = true;
                            });
                          },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDescriptionSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsetsDirectional.only(
            start: 20,
            end: 20,
            top: 8,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.screenLabels.addNote,
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('addExpenseDescriptionField'),
                controller: _descriptionController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.screenLabels.descriptionHint,
                ),
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) {
                  _onUserEdited(OcrSuggestionField.title);
                  setState(() {});
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _ink,
                  foregroundColor: _cream,
                ),
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(widget.screenLabels.done),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPlaceSheet() {
    final controller = TextEditingController(text: _placeLabel ?? '');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsetsDirectional.only(
            start: 20,
            end: 20,
            top: 8,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.screenLabels.addPlace,
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('addExpensePlaceField'),
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.screenLabels.addPlace,
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _ink,
                  foregroundColor: _cream,
                ),
                onPressed: () {
                  final label = controller.text.trim();
                  setState(() {
                    _placeLabel = label.isEmpty ? null : label;
                    _resolvedPlaceId = null;
                    _onUserEdited(OcrSuggestionField.placeLabel);
                  });
                  Navigator.of(sheetContext).pop();
                },
                child: Text(widget.screenLabels.done),
              ),
            ],
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  void _showFxSheet({
    required String tripBase,
    required bool inForeignCurrency,
  }) {
    if (!inForeignCurrency) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsetsDirectional.only(
            start: 20,
            end: 20,
            top: 8,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.labels.convertedAmountLabel(tripBase),
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('addExpenseFxField'),
                controller: _baseOverrideController,
                decoration: InputDecoration(
                  prefixText: _currencySymbol(tripBase),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                onChanged: (_) {
                  _baseOverrideUserTouched = true;
                  _fxRateSource = 'manual';
                },
              ),
              if (_fxRateSource == 'receipt')
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 8),
                  child: Text(
                    widget.labels.fxSourceReceipt,
                    style: Theme.of(sheetContext)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: _graphite),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _ink,
                  foregroundColor: _cream,
                ),
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(widget.screenLabels.done),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReceiptSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_receiptSourcePath != null) ...[
                Padding(
                  padding: const EdgeInsetsDirectional.all(20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_receiptSourcePath!),
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: Text(widget.screenLabels.scanReceipt),
                onTap: (_saving || _ocrLoading)
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        _pickReceipt();
                      },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(widget.screenLabels.removeReceipt),
                onTap: (_saving || _ocrLoading)
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        setState(() {
                          _receiptSourcePath = null;
                          _receiptMetadata = null;
                          _placeLabel = null;
                          _resolvedPlaceId = null;
                          _ocrSuggested.clear();
                          _ocrOriginal.clear();
                          _ocrUsed = false;
                        });
                      },
              ),
            ],
          ),
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
    final actionLabel = widget.mode == AddExpenseMode.proposed
        ? saveLabel
        : widget.screenLabels.title;
    if (cents == null || cents <= 0) return actionLabel;
    final currency = _expenseCurrency.toUpperCase() == tripBase.toUpperCase()
        ? tripBase
        : _expenseCurrency;
    return '$actionLabel · ${formatMoneyFromCents(cents, currency)}';
  }

  int? _shareCentsPerMember({
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
    return (baseCents / memberCount).round();
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
    final inForeignCurrency =
        _expenseCurrency.toUpperCase() != tripBaseCurrency.toUpperCase();
    if (inForeignCurrency &&
        parseAmountToCents(_baseOverrideController.text) == null &&
        _autoBaseCents == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.labels.convertedAmountLabel(tripBaseCurrency)),
        ),
      );
      return;
    }
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

    final description = _effectiveDescription();
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
              description: description,
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
                description: description,
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

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({
    required this.amountText,
    required this.currencySymbol,
    required this.errorText,
  });

  final String amountText;
  final String currencySymbol;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = amountText.trim().isEmpty ? '0.00' : amountText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FittedBox(
          alignment: AlignmentDirectional.centerStart,
          fit: BoxFit.scaleDown,
          child: Text(
            key: const Key('addExpenseAmountDisplay'),
            '$currencySymbol$display',
            maxLines: 1,
            style: theme.textTheme.displaySmall?.copyWith(
              color: _ink,
              fontWeight: FontWeight.w800,
            ),
          ),
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
      ],
    );
  }
}

class _CurrencyPill extends StatelessWidget {
  const _CurrencyPill({
    required this.currency,
    required this.enabled,
    required this.onTap,
  });

  final String currency;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = context.vamoShape;
    return Material(
      color: _mist,
      borderRadius: shape.chipBorderRadius,
      child: InkWell(
        key: const Key('addExpenseCurrencyPill'),
        onTap: enabled ? onTap : null,
        borderRadius: shape.chipBorderRadius,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currency,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 18, color: _graphite),
            ],
          ),
        ),
      ),
    );
  }
}

class _EssentialChip extends StatelessWidget {
  const _EssentialChip({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = context.vamoShape;
    return Material(
      color: _mist,
      borderRadius: shape.chipBorderRadius,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: shape.chipBorderRadius,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FxSummaryRow extends StatelessWidget {
  const _FxSummaryRow({
    required this.preview,
    required this.loading,
    required this.tripBase,
    required this.baseOverrideController,
    required this.currencySymbol,
    required this.convertedAmountLabel,
    required this.fxSourceReceipt,
    required this.fxRateSource,
    required this.enabled,
    required this.onTap,
  });

  final String? preview;
  final bool loading;
  final String tripBase;
  final TextEditingController baseOverrideController;
  final String currencySymbol;
  final String convertedAmountLabel;
  final String fxSourceReceipt;
  final String? fxRateSource;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final converted = baseOverrideController.text.trim();
    final subtitle = loading
        ? '…'
        : preview ??
            (converted.isEmpty
                ? convertedAmountLabel
                : '$currencySymbol$converted');

    return Material(
      color: _mist.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      convertedAmountLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: _graphite,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _jade,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (fxRateSource == 'receipt')
                      Text(
                        fxSourceReceipt,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _graphite,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _graphite),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitControl extends StatelessWidget {
  const _SplitControl({
    required this.labels,
    required this.governanceLabels,
    required this.members,
    required this.sharePreview,
    required this.memberCount,
    required this.onCustomTap,
  });

  final AddExpenseScreenLabels labels;
  final ExpenseGovernanceLabels governanceLabels;
  final List<TripMemberView> members;
  final String? sharePreview;
  final int memberCount;
  final VoidCallback onCustomTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = sharePreview == null
        ? governanceLabels.splitLabel(memberCount)
        : labels.splitEach(sharePreview!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              labels.splitSection,
              style: theme.textTheme.titleSmall?.copyWith(
                color: _ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            _SplitSegmented(
              equalLabel: labels.splitEqual,
              customLabel: labels.splitCustom,
              onCustomTap: onCustomTap,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          summary,
          style: theme.textTheme.bodyMedium?.copyWith(color: _graphite),
        ),
        const SizedBox(height: 10),
        for (final member in members)
          _SplitShareRow(
            name: member.displayName,
            amount: sharePreview,
          ),
      ],
    );
  }
}

class _SplitSegmented extends StatelessWidget {
  const _SplitSegmented({
    required this.equalLabel,
    required this.customLabel,
    required this.onCustomTap,
  });

  final String equalLabel;
  final String customLabel;
  final VoidCallback onCustomTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _mist,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _mist),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SplitSegment(
            key: const Key('addExpenseSplitEqual'),
            label: equalLabel,
            selected: true,
            onTap: () {},
          ),
          _SplitSegment(
            key: const Key('addExpenseSplitCustom'),
            label: customLabel,
            selected: false,
            enabled: false,
            onTap: onCustomTap,
          ),
        ],
      ),
    );
  }
}

class _SplitSegment extends StatelessWidget {
  const _SplitSegment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _ink : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected ? _cream : _graphite,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SplitShareRow extends StatelessWidget {
  const _SplitShareRow({
    required this.name,
    required this.amount,
  });

  final String name;
  final String? amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: _mist,
            child: Text(
              _initial(name),
              style: theme.textTheme.labelSmall?.copyWith(
                color: _ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            amount ?? '—',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _graphite,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
          foregroundColor: _ink,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: isBackspace
            ? const Icon(Icons.backspace_outlined, size: 20)
            : Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
      ),
    );
  }
}
