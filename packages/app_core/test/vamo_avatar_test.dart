import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('VamoAvatar shows initials before silhouette', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: VamoAvatar(
            displayName: 'Maya Chen',
            radius: 24,
          ),
        ),
      ),
    );

    expect(find.text('MC'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsNothing);
  });

  testWidgets('VamoAvatar uses first and last name for multi-part names', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: VamoAvatar(
            displayName: 'Maya Luna Chen',
            radius: 24,
          ),
        ),
      ),
    );

    expect(find.text('MC'), findsOneWidget);
    expect(find.text('ML'), findsNothing);
  });

  testWidgets('VamoAvatar prefers custom initials or alias', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: VamoAvatar(
            displayName: 'Maya Chen',
            initials: 'MZ',
            radius: 24,
          ),
        ),
      ),
    );

    expect(find.text('MZ'), findsOneWidget);
    expect(find.text('MC'), findsNothing);
  });

  testWidgets('VamoAvatar falls back to silhouette without display name', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: VamoAvatar(radius: 24),
        ),
      ),
    );

    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });
}
