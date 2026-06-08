import 'package:flutter/material.dart';

import 'category_catalog.dart';

/// One colored slice for [CategoryDonut].
@immutable
class CategoryDonutSlice {
  const CategoryDonutSlice({
    required this.entry,
    required this.cents,
    required this.fraction,
  });

  final CategoryCatalogEntry entry;
  final int cents;
  final double fraction;
}

/// Aggregates committed expense cents by resolved category key.
Map<String, int> aggregateCategoryCents(
  Iterable<({String? category, int cents})> rows,
) {
  final totals = <String, int>{};
  for (final row in rows) {
    if (row.cents <= 0) continue;
    final key = CategoryCatalog.resolve(row.category).key;
    totals[key] = (totals[key] ?? 0) + row.cents;
  }
  return totals;
}

/// Builds donut slices; [fraction]s sum to 1 when [totalCents] > 0.
List<CategoryDonutSlice> buildCategoryDonutSlices({
  required Iterable<({String? category, int cents})> rows,
  required int totalCents,
}) {
  if (totalCents <= 0) return const [];

  final totals = aggregateCategoryCents(rows);
  if (totals.isEmpty) return const [];

  final slices = <CategoryDonutSlice>[];
  for (final entry in CategoryCatalog.canonical) {
    final cents = totals[entry.key];
    if (cents == null || cents <= 0) continue;
    slices.add(
      CategoryDonutSlice(
        entry: entry,
        cents: cents,
        fraction: cents / totalCents,
      ),
    );
    totals.remove(entry.key);
  }

  for (final entry in totals.entries) {
    final cents = entry.value;
    if (cents <= 0) continue;
    final catalogEntry = CategoryCatalog.resolve(entry.key);
    slices.add(
      CategoryDonutSlice(
        entry: catalogEntry,
        cents: cents,
        fraction: cents / totalCents,
      ),
    );
  }

  return slices;
}
