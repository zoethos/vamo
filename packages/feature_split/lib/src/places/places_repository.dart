import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../expenses/receipt_metadata.dart';
import '../expenses/receipt_ocr_models.dart';
import 'place_geocode.dart';
import 'place_resolve.dart';

final placesRepositoryProvider = Provider<PlacesRepository>((ref) {
  return PlacesRepository(
    db: ref.watch(appDatabaseProvider),
    client: ref.watch(supabaseClientProvider),
    analytics: ref.watch(analyticsProvider),
    syncQueue: ref.watch(syncQueueProvider),
  );
});

bool get placeResolutionSupported => placeGeocodeSupported;

/// Result of resolving a receipt parse + EXIF into a persisted place row.
class ResolvedPlaceResult {
  const ResolvedPlaceResult({this.placeId});

  final String? placeId;
}

class PlacesRepository {
  PlacesRepository({
    required AppDatabase db,
    required SupabaseClient client,
    required Analytics analytics,
    required SyncQueue syncQueue,
  })  : _db = db,
        _client = client,
        _analytics = analytics,
        _syncQueue = syncQueue;

  final AppDatabase _db;
  final SupabaseClient _client;
  final Analytics _analytics;
  final SyncQueue _syncQueue;
  final _uuid = const Uuid();

  PlaceSummary _toSummary(LocalPlace row) => PlaceSummary(
        id: row.id,
        tripId: row.tripId,
        label: row.label,
        address: row.address,
        lat: row.lat,
        lng: row.lng,
        source: row.source,
        confidence: row.confidence,
      );

  Future<PlaceSummary?> getPlaceSummary(String? placeId) async {
    if (placeId == null || placeId.isEmpty) return null;
    final row = await _db.getPlace(placeId);
    return row == null ? null : _toSummary(row);
  }

  Stream<List<PlaceSummary>> watchTripPlaces(String tripId) {
    return _db.watchTripPlaces(tripId).map(
          (rows) => rows.map(_toSummary).toList(),
        );
  }

  Future<ResolvedPlaceResult> resolveFromReceipt({
    required String tripId,
    required ReceiptParseResult parse,
    ReceiptCaptureMetadata? exif,
    Future<GeocodeCoords?> Function(String address)? geocodeOverride,
  }) async {
    final label = parse.merchant?.trim();
    if (label == null || label.isEmpty) {
      return const ResolvedPlaceResult();
    }

    if (!placeResolutionSupported) {
      return const ResolvedPlaceResult();
    }

    final geocoder = geocodeOverride ?? geocodeAddress;
    GeocodeCoords? geocoded;
    final address = parse.address?.trim();
    if (address != null && address.isNotEmpty) {
      geocoded = await geocoder(address);
    }

    final coords = resolvePlaceCoordinates(
      geocoded: geocoded,
      exifLat: exif?.lat,
      exifLng: exif?.lng,
    );

    if (coords == null) {
      return const ResolvedPlaceResult();
    }

    final existing =
        (await _db.listTripPlaces(tripId)).map(_toSummary).toList();
    final duplicateId = findDuplicatePlaceId(
      existing: existing,
      label: label,
      lat: coords.lat,
      lng: coords.lng,
    );
    if (duplicateId != null) {
      _emitPlaceResolved(coords.source, coords.confidence);
      return ResolvedPlaceResult(placeId: duplicateId);
    }

    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const ResolvedPlaceResult();
    }

    final placeId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final storedAddress = coords.keepAddressText ? address : null;

    await _db.upsertPlace(
      LocalPlacesCompanion(
        id: Value(placeId),
        tripId: Value(tripId),
        label: Value(label),
        address: Value(storedAddress),
        lat: Value(coords.lat),
        lng: Value(coords.lng),
        source: Value(coords.source),
        confidence: Value(coords.confidence),
        createdBy: Value(userId),
        createdAt: Value(now),
      ),
    );

    final payload = <String, dynamic>{
      'id': placeId,
      'trip_id': tripId,
      'label': label,
      'source': coords.source,
      'confidence': coords.confidence,
      'created_by': userId,
      'created_at': now.toIso8601String(),
      'lat': coords.lat,
      'lng': coords.lng,
      if (storedAddress != null && storedAddress.isNotEmpty)
        'address': storedAddress,
    };

    await _syncQueue.enqueue(
      kind: SyncKind.placeInsert,
      payload: payload,
    );

    _emitPlaceResolved(coords.source, coords.confidence);
    return ResolvedPlaceResult(placeId: placeId);
  }

  void _emitPlaceResolved(String source, double confidence) {
    _analytics.capture(
      VamoEvent.placeResolved,
      properties: {
        'source': source,
        'confidence_bucket': placeConfidenceBucket(confidence),
      },
    );
  }

  Future<void> syncPlacesForTrips(Iterable<String> tripIds) async {
    final ids = tripIds.toList();
    if (ids.isEmpty) return;

    const selectCols =
        'id, trip_id, label, address, lat, lng, source, confidence, '
        'created_by, created_at';

    final rows = await _client
        .from('places')
        .select(selectCols)
        .inFilter('trip_id', ids)
        .order('created_at', ascending: false);

    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      await _db.upsertPlace(
        LocalPlacesCompanion(
          id: Value(row['id'] as String),
          tripId: Value(row['trip_id'] as String),
          label: Value(row['label'] as String),
          address: Value(row['address'] as String?),
          lat: Value(_nullableDouble(row['lat'])),
          lng: Value(_nullableDouble(row['lng'])),
          source: Value(row['source'] as String),
          confidence: Value((row['confidence'] as num).toDouble()),
          createdBy: Value(row['created_by'] as String),
          createdAt: Value(DateTime.parse(row['created_at'] as String)),
        ),
      );
    }
  }

  double? _nullableDouble(Object? value) {
    if (value == null) return null;
    return (value as num).toDouble();
  }
}
