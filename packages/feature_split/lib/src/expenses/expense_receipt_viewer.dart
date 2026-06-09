import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'expense_models.dart';
import 'expenses_repository.dart';

/// Full-screen receipt viewer (local file or loud failure placeholder).
class ExpenseReceiptViewerScreen extends StatelessWidget {
  const ExpenseReceiptViewerScreen({
    super.key,
    required this.imagePath,
    this.loadError,
    this.onRetry,
  });

  final String? imagePath;
  final Object? loadError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Receipt'),
      ),
      body: loadError != null
          ? StorageUnavailablePlaceholder(
              label: 'Receipt unavailable',
              onRetry: onRetry,
            )
          : Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: path != null && File(path).existsSync()
                    ? Image.file(File(path), fit: BoxFit.contain)
                    : const StorageUnavailablePlaceholder(
                        label: 'Receipt unavailable',
                      ),
              ),
            ),
    );
  }
}

Future<void> openExpenseReceiptViewer(
  BuildContext context,
  WidgetRef ref, {
  required ExpenseSummary expense,
}) async {
  final result =
      await ref.read(expensesRepositoryProvider).loadReceiptAttachment(expense);
  if (!context.mounted) return;

  if (result.error != null && result.hadRemoteAttachment) {
    reportAndLog(
      result.error!,
      StackTrace.current,
      screen: 'trip_home',
      action: 'load_receipt',
      analytics: ref.read(analyticsProvider),
    );
  }

  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ExpenseReceiptViewerScreen(
        imagePath: result.localPath,
        loadError: result.hadRemoteAttachment ? result.error : null,
        onRetry: () {
          Navigator.of(context).pop();
          openExpenseReceiptViewer(context, ref, expense: expense);
        },
      ),
    ),
  );
}
