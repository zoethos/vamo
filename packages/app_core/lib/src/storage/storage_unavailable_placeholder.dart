import 'package:flutter/material.dart';

import '../design/app_colors.dart';

/// Visible failure state when a remote attachment cannot be loaded.
class StorageUnavailablePlaceholder extends StatelessWidget {
  const StorageUnavailablePlaceholder({
    super.key,
    required this.label,
    this.onRetry,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Semantics(
        label: label,
        child: Tooltip(
          message: label,
          child: InkWell(
            onTap: onRetry,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.blush,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.graphite.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    size: 18,
                    color: AppColors.graphite,
                  ),
                  if (onRetry != null)
                    Icon(
                      Icons.refresh,
                      size: 12,
                      color: AppColors.jadeTeal,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 48, color: AppColors.graphite),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.graphite,
                  ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              IconButton(
                tooltip: 'Retry',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                color: AppColors.jadeTeal,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
