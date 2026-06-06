import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'expense_governance.dart';
import 'expense_models.dart';
import 'expense_receipt_viewer.dart';
import 'expenses_repository.dart';
import 'expense_display.dart';
import '../trips/locale_format.dart';

/// Single expense row — shared by trip home and RTL golden tests (T13.4).
class TripExpenseListTile extends ConsumerWidget {
  const TripExpenseListTile({
    super.key,
    required this.description,
    required this.payer,
    required this.spentAt,
    required this.baseCents,
    required this.amountCents,
    required this.tripBaseCurrency,
    required this.expenseCurrency,
    this.locale,
    this.expenseId,
    this.tripId,
    this.receiptPath,
    this.localReceiptPath,
    this.receiptThumbnailPath,
    this.placeLabel,
    this.status = ExpenseStatus.committed,
    this.consentLabel,
    required this.proposalRowPrefix,
    this.onTap,
  });

  final String description;
  final String payer;
  final DateTime spentAt;
  final int baseCents;
  final int amountCents;
  final String tripBaseCurrency;
  final String expenseCurrency;
  final String? locale;
  final String? expenseId;
  final String? tripId;
  final String? receiptPath;
  final String? localReceiptPath;
  final String? receiptThumbnailPath;
  final String? placeLabel;
  final ExpenseStatus status;
  final String? consentLabel;
  final String proposalRowPrefix;
  final VoidCallback? onTap;

  bool get _hasReceipt =>
      receiptThumbnailPath != null ||
      (receiptPath != null && receiptPath!.isNotEmpty) ||
      (localReceiptPath != null && localReceiptPath!.isNotEmpty);

  ExpenseSummary get _expense => ExpenseSummary(
        id: expenseId ?? 'test',
        tripId: tripId ?? 'test',
        description: description,
        amountCents: amountCents,
        baseCents: baseCents,
        currency: expenseCurrency,
        payerId: payer,
        spentAt: spentAt,
        status: status,
        receiptPath: receiptPath,
        localReceiptPath: localReceiptPath,
        placeLabel: placeLabel,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final when = formatShortDate(spentAt, locale: locale);
    var detailLine = (placeLabel != null && placeLabel!.isNotEmpty)
        ? '$placeLabel · $payer · $when'
        : '$payer · $when';
    if (consentLabel != null && consentLabel!.isNotEmpty) {
      detailLine = '$detailLine · $consentLabel';
    }
    if (status == ExpenseStatus.proposed) {
      detailLine = '$proposalRowPrefix · $detailLine';
    }

    Widget? leading;
    if (_hasReceipt) {
      leading = _ReceiptThumbnail(
        key: const Key('expense_receipt_thumbnail'),
        expense: _expense,
        thumbnailOverride: receiptThumbnailPath,
        onOpen: () => openExpenseReceiptViewer(
          context,
          ref,
          expense: _expense,
        ),
      );
    }

    return Card(
      shape: status == ExpenseStatus.proposed
          ? RoundedRectangleBorder(
              side: BorderSide(
                color: AppColors.graphite.withValues(alpha: 0.4),
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      color: status == ExpenseStatus.proposed
          ? AppColors.graphite.withValues(alpha: 0.04)
          : null,
      child: ListTile(
        leading: leading,
        title: Text(
          description,
          style: status == ExpenseStatus.proposed
              ? Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.graphite,
                    fontStyle: FontStyle.italic,
                  )
              : null,
        ),
        subtitle: placeLabel != null && placeLabel!.isNotEmpty
            ? Row(
                children: [
                  const Icon(
                    Icons.place_outlined,
                    size: 14,
                    color: AppColors.graphite,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      detailLine,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.graphite,
                          ),
                    ),
                  ),
                ],
              )
            : Text(
                detailLine,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.graphite,
                    ),
              ),
        trailing: Text(
          formatExpenseTrailing(
            baseCents: baseCents,
            tripBaseCurrency: tripBaseCurrency,
            amountCents: amountCents,
            expenseCurrency: expenseCurrency,
            locale: locale,
          ),
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
        ),
        onTap: onTap ??
            (leading == null
                ? null
                : () => openExpenseReceiptViewer(
                      context,
                      ref,
                      expense: _expense,
                    )),
      ),
    );
  }
}

class _ReceiptThumbnail extends ConsumerStatefulWidget {
  const _ReceiptThumbnail({
    super.key,
    required this.expense,
    required this.onOpen,
    this.thumbnailOverride,
  });

  final ExpenseSummary expense;
  final VoidCallback onOpen;
  final String? thumbnailOverride;

  @override
  ConsumerState<_ReceiptThumbnail> createState() => _ReceiptThumbnailState();
}

class _ReceiptThumbnailState extends ConsumerState<_ReceiptThumbnail> {
  StorageAttachmentLoadResult? _result;
  Object? _lastReportedError;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _ReceiptThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expense.receiptPath != widget.expense.receiptPath ||
        oldWidget.expense.localReceiptPath != widget.expense.localReceiptPath ||
        oldWidget.thumbnailOverride != widget.thumbnailOverride) {
      _result = null;
      _lastReportedError = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    if (widget.thumbnailOverride != null) {
      setState(
        () => _result = StorageAttachmentLoadResult.local(widget.thumbnailOverride!),
      );
      return;
    }
    final result = await ref
        .read(expensesRepositoryProvider)
        .loadReceiptAttachment(widget.expense);
    if (!mounted) return;
    setState(() => _result = result);
    _reportLoadFailure(result);
  }

  void _reportLoadFailure(StorageAttachmentLoadResult result) {
    final error = result.error;
    if (error == null ||
        !result.hadRemoteAttachment ||
        identical(error, _lastReportedError)) {
      return;
    }
    _lastReportedError = error;
    ref.read(analyticsProvider).reportActionFailed(
          screen: 'trip_home',
          action: 'load_receipt',
          error: error,
        );
  }

  @override
  Widget build(BuildContext context) {
    final path = _result?.localPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(path),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
        ),
      );
    }

    if (_result?.error != null && (_result?.hadRemoteAttachment ?? false)) {
      return StorageUnavailablePlaceholder(
        compact: true,
        label: 'Receipt unavailable',
        onRetry: _resolve,
      );
    }

    return const SizedBox(
      width: 48,
      height: 48,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
