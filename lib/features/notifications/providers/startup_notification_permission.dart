import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_environment.dart';
import '../services/customer_alert_platform.dart';

class SavedNotificationPermission {
  const SavedNotificationPermission({
    this.prompted = false,
    this.granted = false,
  });
  final bool prompted, granted;
}

abstract class StartupNotificationPermissionStorage {
  Future<SavedNotificationPermission> read();
  Future<void> write(SavedNotificationPermission value);
}

class DeviceNotificationPermissionStorage
    implements StartupNotificationPermissionStorage {
  final _preferences = SharedPreferencesAsync();
  static const _key = 'koyas.notification.permission.v1';
  @override
  Future<SavedNotificationPermission> read() async {
    final value = await _preferences.getString(_key);
    return SavedNotificationPermission(
      prompted: value == 'allowed' || value == 'declined',
      granted: value == 'allowed',
    );
  }

  @override
  Future<void> write(SavedNotificationPermission value) =>
      _preferences.setString(_key, value.granted ? 'allowed' : 'declined');
}

class StartupNotificationPermissionState {
  const StartupNotificationPermissionState({
    this.ready = false,
    this.granted = false,
    this.newConsent = false,
  });
  final bool ready, granted, newConsent;
}

final startupNotificationPromptEnabledProvider = Provider<bool>(
  (ref) =>
      AppEnvironment.hasSupabaseConfig &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS),
);
final startupNotificationStorageProvider =
    Provider<StartupNotificationPermissionStorage>(
      (ref) => DeviceNotificationPermissionStorage(),
    );
final startupNotificationPermissionProvider =
    NotifierProvider<
      StartupNotificationPermission,
      StartupNotificationPermissionState
    >(StartupNotificationPermission.new);

/// Device permission is requested before sign-in. Account/token activation
/// remains separate and always requires an authenticated customer.
class StartupNotificationPermission
    extends Notifier<StartupNotificationPermissionState> {
  Future<void>? _pending;
  CustomerAlertPlatform? _platform;
  @override
  StartupNotificationPermissionState build() {
    ref.onDispose(() => _platform?.dispose());
    return const StartupNotificationPermissionState();
  }

  Future<void> start() => _pending ??= _start();
  Future<void> _start() async {
    if (!ref.read(startupNotificationPromptEnabledProvider)) return;
    try {
      final storage = ref.read(startupNotificationStorageProvider);
      final saved = await storage.read().timeout(const Duration(seconds: 5));
      if (!ref.mounted) return;
      final platform = _platform ??= ref.read(
        customerAlertPlatformFactoryProvider,
      )();
      var granted = await platform.restore();
      if (!ref.mounted) return;
      var newConsent = granted && saved.prompted && !saved.granted;
      if (!saved.prompted && !granted) {
        // The operating system decides whether an existing denial can be asked
        // again. A saved app decision prevents prompts on every startup.
        granted = await platform.enable();
        newConsent = granted;
      }
      if (!ref.mounted) return;
      state = StartupNotificationPermissionState(
        ready: true,
        granted: granted,
        newConsent: newConsent,
      );
      await storage.write(
        SavedNotificationPermission(prompted: true, granted: granted),
      );
    } catch (_) {
      // Device/preference failures never block sign-in or address entry.
    }
  }
}
