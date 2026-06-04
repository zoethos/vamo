import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analytics/analytics.dart';
import '../analytics/analytics_providers.dart';
import '../analytics/error_kind.dart';
import 'app_colors.dart';

/// Consistent empty state; fires [VamoEvent.emptyStateShown] once (Slice 11).
class AppEmptyState extends ConsumerStatefulWidget {
  const AppEmptyState({
    super.key,
    required this.screen,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final String screen;
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  ConsumerState<AppEmptyState> createState() => _AppEmptyStateState();
}

class _AppEmptyStateState extends ConsumerState<AppEmptyState> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analyticsProvider).capture(
            VamoEvent.emptyStateShown,
            properties: {'screen': widget.screen},
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 56, color: AppColors.teal),
            const SizedBox(height: 16),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: AppColors.tealDark,
              ),
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Consistent error + retry; fires [VamoEvent.errorShown] once (Slice 11).
class AppErrorState extends ConsumerStatefulWidget {
  const AppErrorState({
    super.key,
    required this.screen,
    required this.message,
    this.kind = AnalyticsErrorKind.unknown,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  final String screen;
  final String message;
  final AnalyticsErrorKind kind;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  ConsumerState<AppErrorState> createState() => _AppErrorStateState();
}

class _AppErrorStateState extends ConsumerState<AppErrorState> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analyticsProvider).capture(
            VamoEvent.errorShown,
            properties: {
              'screen': widget.screen,
              'kind': widget.kind.value,
            },
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 48, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(widget.message, textAlign: TextAlign.center),
            if (widget.onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: widget.onRetry,
                child: Text(widget.retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
