import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// Test override — skips async resolution.
  final String? receiptThumbnailPath;

  bool get _hasReceipt =>
      receiptThumbnailPath != null ||
      (receiptPath != null && receiptPath!.isNotEmpty) ||
      (localReceiptPath != null && localReceiptPath!.isNotEmpty);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final when = formatShortDate(spentAt, locale: locale);
    Widget? leading;
    if (_hasReceipt) {
      leading = _ReceiptThumbnail(
        key: const Key('expense_receipt_thumbnail'),
        expense: ExpenseSummary(
          id: expenseId ?? 'test',
          tripId: tripId ?? 'test',
          description: description,
          amountCents: amountCents,
          baseCents: baseCents,
          currency: expenseCurrency,
          payerId: payer,
          spentAt: spentAt,
          receiptPath: receiptPath,
          localReceiptPath: localReceiptPath,
        ),
        thumbnailOverride: receiptThumbnailPath,
        onOpen: (path) => openExpenseReceiptViewer(context, imagePath: path),
      );
    }

    return Card(
      child: ListTile(
        leading: leading,
        title: Text(description),
        subtitle: Text('$payer · $when'),
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
                color: AppColors.tealDark,
                fontWeight: FontWeight.w600,
              ),
        ),
        onTap: leading == null
            ? null
            : () async {
                if (receiptThumbnailPath != null) {
                  await openExpenseReceiptViewer(
                    context,
                    imagePath: receiptThumbnailPath!,
                  );
                  return;
                }
                final expense = ExpenseSummary(
                  id: expenseId!,
                  tripId: tripId!,
                  description: description,
                  amountCents: amountCents,
                  baseCents: baseCents,
                  currency: expenseCurrency,
                  payerId: payer,
                  spentAt: spentAt,
                  receiptPath: receiptPath,
                  localReceiptPath: localReceiptPath,
                );
                final path = await ref
                    .read(expensesRepositoryProvider)
                    .resolveReceiptDisplayPath(expense);
                if (!context.mounted || path == null) return;
                await openExpenseReceiptViewer(context, imagePath: path);
              },
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
  final void Function(String path) onOpen;
  final String? thumbnailOverride;

  @override
  ConsumerState<_ReceiptThumbnail> createState() => _ReceiptThumbnailState();
}

class _ReceiptThumbnailState extends ConsumerState<_ReceiptThumbnail> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    if (widget.thumbnailOverride != null) {
      setState(() => _path = widget.thumbnailOverride);
      return;
    }
    final path = await ref
        .read(expensesRepositoryProvider)
        .resolveReceiptDisplayPath(widget.expense);
    if (mounted) setState(() => _path = path);
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    if (path != null && File(path).existsSync()) {
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
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.sandLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.receipt_long_outlined,
        color: AppColors.teal,
      ),
    );
  }
}
