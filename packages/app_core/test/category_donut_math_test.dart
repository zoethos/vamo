import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildCategoryDonutSlices fractions sum to one', () {
    final slices = buildCategoryDonutSlices(
      rows: const [
        (category: 'food', cents: 6000),
        (category: 'transport', cents: 4000),
      ],
      totalCents: 10000,
    );
    expect(slices, hasLength(2));
    final sum = slices.fold<double>(0, (s, e) => s + e.fraction);
    expect(sum, closeTo(1.0, 0.0001));
    expect(slices.first.cents + slices.last.cents, 10000);
  });

  test('buildCategoryDonutSlices empty when total is zero', () {
    final slices = buildCategoryDonutSlices(
      rows: const [(category: 'food', cents: 100)],
      totalCents: 0,
    );
    expect(slices, isEmpty);
  });

  test('buildCategoryDonutSlices single category is full ring', () {
    final slices = buildCategoryDonutSlices(
      rows: const [(category: 'lodging', cents: 2500)],
      totalCents: 2500,
    );
    expect(slices, hasLength(1));
    expect(slices.single.fraction, closeTo(1.0, 0.0001));
    expect(slices.single.entry.key, 'lodging');
  });

  test('CategoryCatalog resolves unknown free-text deterministically', () {
    final a = CategoryCatalog.resolve('surf lessons');
    final b = CategoryCatalog.resolve('surf lessons');
    final c = CategoryCatalog.resolve('zzzzzzzzzz');
    expect(a.color, b.color);
    expect(a.key, b.key);
    expect(c.key, isNot(a.key));
    expect(a.icon, CategoryCatalog.other.icon);
  });
}
