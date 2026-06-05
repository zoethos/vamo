import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'coming_soon_sheet.dart';

/// Compact "coming soon" door on trip home (map / recap).
class ComingSoonTeaser extends ConsumerWidget {
  const ComingSoonTeaser({
    super.key,
    required this.interestEvent,
    required this.feature,
    required this.title,
    required this.icon,
  });

  final VamoEvent interestEvent;
  final String feature;
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showComingSoonSheet(
          context: context,
          ref: ref,
          interestEvent: interestEvent,
          feature: feature,
          title: title,
          description: _descriptionFor(feature),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: AppColors.teal, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      'Coming soon',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left
                    : Icons.chevron_right,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _descriptionFor(String feature) {
    return switch (feature) {
      'map' =>
        'See where you went on a shared map — pins from capture and expenses.',
      'recap' =>
        'A short trip recap video from your photos and highlights.',
      _ => 'Something new for Vamo trips.',
    };
  }
}
