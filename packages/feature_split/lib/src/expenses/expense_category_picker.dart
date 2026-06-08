import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

/// Choice chips for canonical expense categories (S40).
class ExpenseCategoryPicker extends StatelessWidget {
  const ExpenseCategoryPicker({
    super.key,
    required this.selectedKey,
    required this.onChanged,
    this.enabled = true,
    this.label = 'Category',
  });

  final String? selectedKey;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String label;

  @override
  Widget build(BuildContext context) {
    final selected = selectedKey ?? CategoryCatalog.other.key;
    final type = context.vamoType;

    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in CategoryCatalog.canonical)
            ChoiceChip(
              selected: selected == entry.key,
              onSelected: enabled ? (_) => onChanged(entry.key) : null,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(entry.icon, size: 18, color: entry.color),
                  const SizedBox(width: 6),
                  Text(
                    entry.label,
                    style: type.labelMedium.copyWith(color: entry.color),
                  ),
                ],
              ),
              selectedColor: entry.color.withValues(alpha: 0.18),
              side: BorderSide(
                color: entry.color.withValues(alpha: selected == entry.key ? 0.9 : 0.45),
              ),
              showCheckmark: false,
            ),
        ],
      ),
    );
  }
}
