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

/// Derives a short, human row title from a raw expense [description] (§A).
///
/// Takes the first segment before a `·` separator (the long legal name —
/// e.g. "BORRI BOOKS · SOC, TBRERIA TERMINI SRL" — lives in the detail sheet),
/// caps it at three words, and Title-Cases SHOUTING all-caps names so the row
/// reads "Borri Books", not the full registry name. Non-caps input is kept
/// verbatim ("Ferry tickets" stays as-is).
String shortMerchantName(String description) {
  final firstSegment = description.split('·').first.trim();
  final words =
      firstSegment.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final base = words.isEmpty ? description.trim() : words.take(3).join(' ');
  final hasLetters = base.toLowerCase() != base.toUpperCase();
  final isShouting = hasLetters && base == base.toUpperCase();
  if (!isShouting) return base;
  return base
      .split(' ')
      .map((w) =>
          w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

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
    this.category,
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
  final String? category;
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
        category: category,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final when = formatShortDate(spentAt, locale: locale);
    // Meta reads payer · place · date (§A) — the merchant lives in the title,
    // not repeated here.
    final metaParts = <String>[
      payer,
      if (placeLabel != null && placeLabel!.isNotEmpty) placeLabel!,
      when,
    ];
    var detailLine = metaParts.join(' · ');
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
    } else {
      leading = _CategoryLeading(category: category);
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
          shortMerchantName(description),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
            (_hasReceipt
                ? () => openExpenseReceiptViewer(
                      context,
                      ref,
                      expense: _expense,
                    )
                : null),
      ),
    );
  }
}

class _CategoryLeading extends StatelessWidget {
  const _CategoryLeading({this.category});

  final String? category;

  @override
  Widget build(BuildContext context) {
    final entry = CategoryCatalog.resolve(category);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: entry.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Icon(entry.icon, color: entry.color, size: 22),
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
        () => _result =
            StorageAttachmentLoadResult.local(widget.thumbnailOverride!),
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
    reportAndLog(
      error,
      StackTrace.current,
      screen: 'trip_home',
      action: 'load_receipt',
      analytics: ref.read(analyticsProvider),
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
