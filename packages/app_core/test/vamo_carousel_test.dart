import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VamoCarousel widget', () {
    Future<void> pumpCarousel(
      WidgetTester tester, {
      required List<VamoCarouselItem> items,
      int? loadingIndex,
      TextScaler textScaler = TextScaler.noScaling,
    }) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Center(
                child: VamoCarousel(items: items, loadingIndex: loadingIndex),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows vertical wheel with centered noun label only', (
      tester,
    ) async {
      await pumpCarousel(
        tester,
        items: const [
          VamoCarouselItem(
            icon: Icons.photo_camera_rounded,
            label: 'Photo',
            onSelected: _noop,
          ),
          VamoCarouselItem(
            icon: Icons.videocam_rounded,
            label: 'Video',
            onSelected: _noop,
          ),
        ],
      );

      expect(find.byType(ListWheelScrollView), findsOneWidget);
      expect(find.byType(VamoCircleIcon), findsWidgets);
      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Video'), findsNothing);
    });

    testWidgets('centered label respects large text scaler without overflow', (
      tester,
    ) async {
      await pumpCarousel(
        tester,
        items: const [
          VamoCarouselItem(
            icon: Icons.photo_camera_rounded,
            label: 'Photo',
            onSelected: _noop,
          ),
        ],
        textScaler: const TextScaler.linear(2),
      );

      final label = tester.widget<Text>(find.text('Photo'));
      expect(label.maxLines, 1);
      expect(
        find.ancestor(of: find.text('Photo'), matching: find.byType(FittedBox)),
        findsOneWidget,
      );
    });

    testWidgets('long centered label scales down to fit the pill', (tester) async {
      await pumpCarousel(
        tester,
        items: const [
          VamoCarouselItem(
            icon: Icons.photo_camera_rounded,
            label: 'Photo',
            onSelected: _noop,
          ),
          VamoCarouselItem(
            icon: Icons.wallpaper_rounded,
            label: 'Background',
            onSelected: _noop,
          ),
        ],
      );

      final wheel = find.byType(ListWheelScrollView);
      await tester.drag(wheel, const Offset(0, -240));
      await tester.pumpAndSettle();

      expect(find.text('Background'), findsOneWidget);
    });

    testWidgets('exposes semantic labels for every option', (tester) async {
      await pumpCarousel(
        tester,
        items: _sampleItems,
      );

      for (final label in ['Photo', 'Video', 'Note', 'Background']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
    });

    testWidgets('semantic options are buttons reachable without scrolling', (
      tester,
    ) async {
      await pumpCarousel(tester, items: _sampleItems);

      for (final label in ['Photo', 'Video', 'Note', 'Background']) {
        final data =
            tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
      }
    });

    testWidgets('wheel is finite and does not wrap end-to-start', (tester) async {
      await pumpCarousel(tester, items: _sampleItems);

      final wheel =
          tester.widget<ListWheelScrollView>(find.byType(ListWheelScrollView));
      expect(wheel.childDelegate.estimatedChildCount, 4);
    });
  });

  group('showVamoCarousel overlay', () {
    testWidgets('outside tap dismisses flyout', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showVamoCarousel(
                    context: context,
                    items: _sampleItems,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(VamoCarousel), findsOneWidget);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(find.byType(VamoCarousel), findsNothing);
    });

    testWidgets('dummy items prove reuse without capture dependencies', (
      tester,
    ) async {
      var selected = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showVamoCarousel(
                    context: context,
                    items: [
                      VamoCarouselItem(
                        icon: Icons.star_outline,
                        label: 'Star',
                        onSelected: () async {
                          selected = true;
                        },
                      ),
                    ],
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tapAt(tester.getCenter(find.byType(VamoCarousel)));
      await tester.pumpAndSettle();

      expect(selected, isTrue);
    });
  });
}

Future<void> _noop() async {}

const _sampleItems = [
  VamoCarouselItem(
    icon: Icons.photo_camera_rounded,
    label: 'Photo',
    onSelected: _noop,
  ),
  VamoCarouselItem(
    icon: Icons.videocam_rounded,
    label: 'Video',
    onSelected: _noop,
  ),
  VamoCarouselItem(
    icon: Icons.edit_note_rounded,
    label: 'Note',
    onSelected: _noop,
  ),
  VamoCarouselItem(
    icon: Icons.wallpaper_rounded,
    label: 'Background',
    onSelected: _noop,
  ),
];
