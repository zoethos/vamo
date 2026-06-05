import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

/// Lime hint chip marking a field pre-filled from receipt OCR.
class OcrSuggestionChip extends StatelessWidget {
  const OcrSuggestionChip({super.key, this.label = 'from receipt'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 6),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Chip(
          visualDensity: VisualDensity.compact,
          label: Text(
            label,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          backgroundColor: AppColors.goLime.withValues(alpha: 0.35),
          side: BorderSide.none,
        ),
      ),
    );
  }
}
