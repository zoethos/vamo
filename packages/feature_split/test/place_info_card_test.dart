import 'package:app_core/app_core.dart';
import 'package:feature_split/src/poi/place_info_card.dart';
import 'package:feature_split/src/poi/poi_models.dart';
import 'package:feature_split/src/shared/vamo_slidable_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PlaceInfo.fromPoi carries provider place details', () {
    const poi = PoiSummary(
      id: 'fsq-1',
      name: 'Abbazia di Montecassino',
      category: PoiCategory.attraction,
      lat: 41.49,
      lng: 13.81,
      source: 'foursquare',
      providerPlaceId: 'fsq-1',
      address: 'Via Montecassino',
      about: 'Historic abbey above Cassino.',
      website: 'https://example.com',
      phone: '+390000',
      hours: 'Mon-Sun 09:00-17:00',
      rating: 9.1,
      priceLevel: 2,
      photoUrl: 'https://img.example/place.jpg',
    );

    final info = PlaceInfo.fromPoi(poi);

    expect(info.name, 'Abbazia di Montecassino');
    expect(info.category, PoiCategory.attraction);
    expect(info.about, 'Historic abbey above Cassino.');
    expect(info.sourceLabel, 'Foursquare');
  });

  testWidgets('PlaceInfoCard renders core place details', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: PlaceInfoCard(
            info: PlaceInfo(
              name: 'Abbazia di Montecassino',
              category: PoiCategory.attraction,
              address: 'Via Montecassino',
              about: 'Historic abbey above Cassino.',
              hours: 'Mon-Sun 09:00-17:00',
              rating: 9.1,
              priceLevel: 2,
              sourceLabel: 'Foursquare',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Abbazia di Montecassino'), findsOneWidget);
    expect(find.text('Historic abbey above Cassino.'), findsOneWidget);
    expect(find.text('Place data: Foursquare'), findsOneWidget);
    expect(find.text(r'Price $$'), findsOneWidget);
    expect(find.text('Hours Mon-Sun 09:00-17:00'), findsOneWidget);
  });

  testWidgets('VamoSlidableRow exposes optional info action', (tester) async {
    var infoTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: VamoSlidableRow(
            infoLabel: 'Info',
            onInfo: () => infoTapped = true,
            child: const ListTile(title: Text('Place row')),
          ),
        ),
      ),
    );

    final slidable = tester.widget<Slidable>(find.byType(Slidable));
    expect(slidable.endActionPane, isNotNull);

    await tester.longPress(find.text('Place row'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();

    expect(infoTapped, isTrue);
  });
}
