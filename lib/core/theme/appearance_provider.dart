import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class AppearanceStorage {
  Future<ThemeMode> read();
  Future<void> write(ThemeMode mode);
}

class DeviceAppearanceStorage implements AppearanceStorage {
  final _preferences = SharedPreferencesAsync();
  static const _key = 'koyas.appearance.v1';

  @override
  Future<ThemeMode> read() async {
    try {
      final value = await _preferences.getString(_key);
      return ThemeMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {
      return ThemeMode.system;
    }
  }

  @override
  Future<void> write(ThemeMode mode) => _preferences.setString(_key, mode.name);
}

final appearanceStorageProvider = Provider<AppearanceStorage>(
  (ref) => DeviceAppearanceStorage(),
);

// Entrypoints restore appearance before the first frame. Preview/test hosts
// can let the controller restore it instead.
final initialAppearanceProvider = Provider<ThemeMode?>((ref) => null);
final appearanceProvider = NotifierProvider<AppearanceController, ThemeMode>(
  AppearanceController.new,
);

class AppearanceController extends Notifier<ThemeMode> {
  int _revision = 0;
  Future<void> _writes = Future.value();

  @override
  ThemeMode build() {
    final initial = ref.read(initialAppearanceProvider);
    if (initial != null) return initial;
    final revision = _revision;
    unawaited(_restore(revision));
    return ThemeMode.system;
  }

  Future<void> _restore(int revision) async {
    try {
      final mode = await ref.read(appearanceStorageProvider).read();
      if (ref.mounted && revision == _revision) state = mode;
    } catch (_) {
      // Shopping remains available if device preferences cannot be read.
    }
  }

  Future<void> select(ThemeMode mode) {
    _revision++;
    state = mode;
    final storage = ref.read(appearanceStorageProvider);
    // Rapid choices are persisted in order; an older write cannot win.
    _writes = _writes
        .catchError((Object _) {})
        .then((_) => storage.write(mode));
    return _writes;
  }
}
