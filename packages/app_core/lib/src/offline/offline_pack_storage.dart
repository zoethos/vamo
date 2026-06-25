import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'offline_pack_models.dart';

/// Stores only small key material for encrypted offline tiers. Bulk ciphertext
/// belongs in Drift or files, referenced by the offline-pack manifest.
abstract class OfflinePackSecureKeyStore {
  Future<String?> readKey({
    required String tripId,
    OfflinePackTier tier = OfflinePackTier.essentials,
  });

  Future<void> writeKey({
    required String tripId,
    required String key,
    OfflinePackTier tier = OfflinePackTier.essentials,
  });

  Future<void> deleteKey({
    required String tripId,
    OfflinePackTier tier = OfflinePackTier.essentials,
  });

  Future<String> getOrCreateKey({
    required String tripId,
    OfflinePackTier tier = OfflinePackTier.essentials,
  }) async {
    final existing = await readKey(tripId: tripId, tier: tier);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = generateOfflinePackDataKey();
    await writeKey(tripId: tripId, tier: tier, key: created);
    return created;
  }
}

class FlutterSecureOfflinePackKeyStore extends OfflinePackSecureKeyStore {
  FlutterSecureOfflinePackKeyStore({
    FlutterSecureStorage? storage,
    String namespace = 'offline_pack',
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _namespace = namespace;

  final FlutterSecureStorage _storage;
  final String _namespace;

  @override
  Future<String?> readKey({
    required String tripId,
    OfflinePackTier tier = OfflinePackTier.essentials,
  }) {
    return _storage.read(key: _key(tripId, tier));
  }

  @override
  Future<void> writeKey({
    required String tripId,
    required String key,
    OfflinePackTier tier = OfflinePackTier.essentials,
  }) {
    return _storage.write(key: _key(tripId, tier), value: key);
  }

  @override
  Future<void> deleteKey({
    required String tripId,
    OfflinePackTier tier = OfflinePackTier.essentials,
  }) {
    return _storage.delete(key: _key(tripId, tier));
  }

  String _key(String tripId, OfflinePackTier tier) {
    return '$_namespace:${tier.value}:$tripId:data_key';
  }
}

class MemoryOfflinePackKeyStore extends OfflinePackSecureKeyStore {
  final Map<String, String> _keys = {};

  @override
  Future<String?> readKey({
    required String tripId,
    OfflinePackTier tier = OfflinePackTier.essentials,
  }) async {
    return _keys[_key(tripId, tier)];
  }

  @override
  Future<void> writeKey({
    required String tripId,
    required String key,
    OfflinePackTier tier = OfflinePackTier.essentials,
  }) async {
    _keys[_key(tripId, tier)] = key;
  }

  @override
  Future<void> deleteKey({
    required String tripId,
    OfflinePackTier tier = OfflinePackTier.essentials,
  }) async {
    _keys.remove(_key(tripId, tier));
  }

  String _key(String tripId, OfflinePackTier tier) {
    return '${tier.value}:$tripId';
  }
}

String generateOfflinePackDataKey({Random? random, int bytes = 32}) {
  final source = random ?? Random.secure();
  final data = List<int>.generate(bytes, (_) => source.nextInt(256));
  return base64UrlEncode(data);
}
