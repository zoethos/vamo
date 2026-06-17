import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../analytics/action_failure.dart';

abstract interface class CaptureLocationTaggingPersistence {
  Future<bool?> read();
  Future<void> write(bool enabled);
}

class FileCaptureLocationTaggingPersistence
    implements CaptureLocationTaggingPersistence {
  const FileCaptureLocationTaggingPersistence();

  static const _fileName = 'vamo_capture_location_tagging.txt';

  @override
  Future<bool?> read() async {
    final file = await _preferenceFile();
    if (file == null || !await file.exists()) return null;
    final raw = (await file.readAsString()).trim().toLowerCase();
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    return null;
  }

  @override
  Future<void> write(bool enabled) async {
    final file = await _preferenceFile();
    if (file == null) return;
    await file.writeAsString(enabled.toString());
  }

  static Future<File?> _preferenceFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_fileName');
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'settings',
        action: 'capture_location_tagging_file',
        severity: ActionFailureSeverity.degraded,
      );
      return null;
    }
  }
}

class NoopCaptureLocationTaggingPersistence
    implements CaptureLocationTaggingPersistence {
  const NoopCaptureLocationTaggingPersistence();

  @override
  Future<bool?> read() async => null;

  @override
  Future<void> write(bool enabled) async {}
}

class CaptureLocationTaggingController extends StateNotifier<bool> {
  CaptureLocationTaggingController({
    CaptureLocationTaggingPersistence persistence =
        const FileCaptureLocationTaggingPersistence(),
    bool initialEnabled = false,
  })  : _persistence = persistence,
        super(initialEnabled) {
    unawaited(_load());
  }

  final CaptureLocationTaggingPersistence _persistence;

  Future<void> _load() async {
    final saved = await _persistence.read();
    if (saved != null) state = saved;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _persistence.write(enabled);
  }
}

/// Opt-in gate for storing capture photo EXIF location metadata.
final captureLocationTaggingProvider =
    StateNotifierProvider<CaptureLocationTaggingController, bool>(
  (ref) => CaptureLocationTaggingController(),
);
