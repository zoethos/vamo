import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// In-memory platform paths for widget tests — avoids [MissingPluginException]
/// when [TripBackgroundStorage] or Drift resolve directories.
class FakePathProviderPlatform extends PathProviderPlatform {
  FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

PathProviderPlatform? _savedPathProvider;
Directory? _pathProviderRoot;

/// Installs fake [PathProviderPlatform] and method-channel handlers for tests.
void setUpFakePathProvider() {
  _savedPathProvider = PathProviderPlatform.instance;
  _pathProviderRoot = Directory.systemTemp.createTempSync('vamo_path_provider_');
  PathProviderPlatform.instance =
      FakePathProviderPlatform(_pathProviderRoot!.path);

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getTemporaryDirectory':
        case 'getApplicationSupportDirectory':
          return _pathProviderRoot!.path;
        default:
          return null;
      }
    },
  );
}

/// Restores platform/channel mocks and deletes the temp directory.
void tearDownFakePathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    null,
  );
  if (_savedPathProvider != null) {
    PathProviderPlatform.instance = _savedPathProvider!;
    _savedPathProvider = null;
  }
  final root = _pathProviderRoot;
  _pathProviderRoot = null;
  if (root != null) {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold open handles from Image/File widgets.
    }
  }
}

/// Temp directory root used by the active fake path provider, if any.
Directory? get fakePathProviderRoot => _pathProviderRoot;
