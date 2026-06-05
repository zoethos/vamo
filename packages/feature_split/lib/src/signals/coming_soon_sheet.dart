import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Intention door — "coming soon" sheet + optional notify-me (spec §8b layer 3).
Future<void> showComingSoonSheet({
  required BuildContext context,
  required WidgetRef ref,
  required VamoEvent interestEvent,
  required String feature,
  required String title,
  required String description,
}) async {
  ref.read(analyticsProvider).capture(interestEvent);

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                    color: AppColors.tealDark,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(ctx)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            Text(
              'Coming soon — we are building this for a later wave.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                    fontStyle: FontStyle.italic,
                  ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                ref.read(analyticsProvider).capture(
                      VamoEvent.notifyMeOptedIn,
                      properties: {'feature': feature},
                    );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Got it — we will let you know.'),
                  ),
                );
              },
              child: const Text('Tell me when it is ready'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    },
  );
}
