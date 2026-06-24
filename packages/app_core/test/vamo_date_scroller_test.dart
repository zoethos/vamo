import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openScroller(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showVamoDateScroller(
                  context: context,
                  initialStart: DateTime(2026, 5, 12),
                  initialEnd: DateTime(2026, 5, 12),
                  firstDate: DateTime(2026, 5, 8),
                  lastDate: DateTime(2026, 6, 14),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('second tap extends range and third tap restarts', (
    tester,
  ) async {
    await openScroller(tester);

    expect(find.text('Use May 12'), findsOneWidget);

    await tester.tap(find.text('18'));
    await tester.pumpAndSettle();
    expect(find.text('Use 7 days'), findsOneWidget);

    await tester.tap(find.text('14'));
    await tester.pumpAndSettle();
    expect(find.text('Use May 14'), findsOneWidget);
  });

  testWidgets('times stay collapsed until the user asks for them', (
    tester,
  ) async {
    await openScroller(tester);

    expect(find.text('START TIME'), findsNothing);

    await tester.tap(find.text('Add times'));
    await tester.pumpAndSettle();
    expect(find.text('START TIME'), findsOneWidget);

    await tester.tap(find.text('10:00'));
    await tester.pumpAndSettle();
    expect(find.text('Use May 12 · 10:00'), findsOneWidget);
  });
}
