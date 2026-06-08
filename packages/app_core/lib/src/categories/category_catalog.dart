import 'package:flutter/material.dart';

import '../design/app_colors.dart';

/// Canonical expense category metadata — single source for donut + activity icons.
@immutable
class CategoryCatalogEntry {
  const CategoryCatalogEntry({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String key;
  final String label;
  final IconData icon;
  final Color color;
}

/// Built-in categories aligned with S35 / travel reference board.
abstract final class CategoryCatalog {
  static const food = CategoryCatalogEntry(
    key: 'food',
    label: 'Food',
    icon: Icons.restaurant,
    color: AppColors.sunrise,
  );

  static const lodging = CategoryCatalogEntry(
    key: 'lodging',
    label: 'Lodging',
    icon: Icons.hotel,
    color: AppColors.jadeTeal,
  );

  static const transport = CategoryCatalogEntry(
    key: 'transport',
    label: 'Transport',
    icon: Icons.directions_car,
    color: AppColors.sky,
  );

  static const activities = CategoryCatalogEntry(
    key: 'activities',
    label: 'Activities',
    icon: Icons.local_activity,
    color: AppColors.sunsetCoral,
  );

  static const shopping = CategoryCatalogEntry(
    key: 'shopping',
    label: 'Shopping',
    icon: Icons.shopping_bag,
    color: AppColors.mango,
  );

  static const other = CategoryCatalogEntry(
    key: 'other',
    label: 'Other',
    icon: Icons.more_horiz,
    color: AppColors.neutralMid,
  );

  static const List<CategoryCatalogEntry> canonical = [
    food,
    lodging,
    transport,
    activities,
    shopping,
    other,
  ];

  static final Map<String, CategoryCatalogEntry> _byKey = {
    for (final e in canonical) e.key: e,
  };

  static const _aliases = <String, String>{
    'dining': 'food',
    'restaurant': 'food',
    'meal': 'food',
    'meals': 'food',
    'hotel': 'lodging',
    'accommodation': 'lodging',
    'stay': 'lodging',
    'flight': 'transport',
    'flights': 'transport',
    'taxi': 'transport',
    'uber': 'transport',
    'train': 'transport',
    'activity': 'activities',
    'tour': 'activities',
    'tours': 'activities',
    'entertainment': 'activities',
    'shop': 'shopping',
    'grocery': 'shopping',
    'groceries': 'shopping',
    'misc': 'other',
    'miscellaneous': 'other',
    'general': 'other',
  };

  /// Resolves free-text [raw] to a catalog entry (never null).
  static CategoryCatalogEntry resolve(String? raw) {
    final normalized = _normalize(raw);
    if (normalized.isEmpty) return other;
    final direct = _byKey[normalized];
    if (direct != null) return direct;
    final alias = _aliases[normalized];
    if (alias != null) return _byKey[alias] ?? other;
    return CategoryCatalogEntry(
      key: normalized,
      label: _titleCase(normalized),
      icon: other.icon,
      color: colorForUnknown(normalized),
    );
  }

  /// Deterministic accent for unknown free-text categories.
  static Color colorForUnknown(String normalizedKey) {
    final palette = [
      AppColors.deepTeal,
      AppColors.apricot,
      AppColors.deepPlum,
      AppColors.coralText,
      AppColors.indigo,
    ];
    var hash = 0;
    for (final code in normalizedKey.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  static String _normalize(String? raw) {
    if (raw == null) return '';
    return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
