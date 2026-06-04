import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'fx_snapshot.dart';

/// Last-known pivot FX snapshot on disk — survives app restarts for offline foreign expenses.
abstract final class FxRatesPersistence {
  static const _fileName = 'fx_rates_pivot_cache.json';

  static Future<FxRatesSnapshot?> load() async {
    try {
      final file = await _cacheFile();
      if (file == null || !await file.exists()) return null;
      final body = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return FxRatesSnapshot.fromJson(body);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[fx] could not load persisted rates: $e');
      }
      return null;
    }
  }

  static Future<void> save(FxRatesSnapshot pivot) async {
    try {
      final file = await _cacheFile();
      if (file == null) return;
      await file.writeAsString(jsonEncode(pivot.toJson()));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[fx] could not persist rates: $e');
      }
    }
  }

  static Future<File?> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }
}
