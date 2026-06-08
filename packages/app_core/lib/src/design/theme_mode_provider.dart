import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// User-facing theme preference for light/dark inspection.
enum VamoThemePreference {
  light,
  dark,
  system,
  ;

  static VamoThemePreference? parse(String? raw) {
    if (raw == null) return null;
    for (final value in VamoThemePreference.values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

extension VamoThemePreferenceMode on VamoThemePreference {
  ThemeMode get themeMode => switch (this) {
        VamoThemePreference.light => ThemeMode.light,
        VamoThemePreference.dark => ThemeMode.dark,
        VamoThemePreference.system => ThemeMode.system,
      };
}

abstract interface class ThemePreferencePersistence {
  Future<VamoThemePreference?> read();
  Future<void> write(VamoThemePreference preference);
}

class FileThemePreferencePersistence implements ThemePreferencePersistence {
  const FileThemePreferencePersistence();

  static const _fileName = 'vamo_theme_preference.txt';

  @override
  Future<VamoThemePreference?> read() async {
    final file = await _preferenceFile();
    if (file == null || !await file.exists()) return null;
    final raw = (await file.readAsString()).trim();
    return VamoThemePreference.parse(raw);
  }

  @override
  Future<void> write(VamoThemePreference preference) async {
    final file = await _preferenceFile();
    if (file == null) return;
    await file.writeAsString(preference.name);
  }

  static Future<File?> _preferenceFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }
}

class NoopThemePreferencePersistence implements ThemePreferencePersistence {
  const NoopThemePreferencePersistence();

  @override
  Future<VamoThemePreference?> read() async => null;

  @override
  Future<void> write(VamoThemePreference preference) async {}
}

class ThemePreferenceController extends StateNotifier<VamoThemePreference> {
  ThemePreferenceController({
    ThemePreferencePersistence persistence =
        const FileThemePreferencePersistence(),
    VamoThemePreference initialPreference = VamoThemePreference.light,
  })  : _persistence = persistence,
        super(initialPreference) {
    unawaited(_load());
  }

  final ThemePreferencePersistence _persistence;

  Future<void> _load() async {
    final saved = await _persistence.read();
    if (saved != null) state = saved;
  }

  Future<void> setPreference(VamoThemePreference preference) async {
    state = preference;
    await _persistence.write(preference);
  }
}

/// Defaults to light so dark mode is opt-in during polish.
final themePreferenceProvider =
    StateNotifierProvider<ThemePreferenceController, VamoThemePreference>(
  (ref) => ThemePreferenceController(),
);
