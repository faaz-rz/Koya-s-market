import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PushPreference {
  const PushPreference({this.enabled = false, this.sound = true});
  final bool enabled, sound;
}

abstract class PushPreferences {
  Future<PushPreference> read(String user);
  Future<void> write(String user, PushPreference value);
}

final pushPreferencesProvider = Provider<PushPreferences>(
  (ref) => SecurePushPreferences(),
);

class SecurePushPreferences implements PushPreferences {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'koyas_push',
      resetOnError: true,
      migrateWithBackup: false,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );
  @override
  Future<PushPreference> read(String user) async {
    try {
      final value = jsonDecode(await _storage.read(key: 'push.$user') ?? '{}');
      return PushPreference(
        enabled: value['enabled'] == true,
        sound: value['sound'] != false,
      );
    } catch (_) {
      return const PushPreference();
    }
  }

  @override
  Future<void> write(String user, PushPreference value) => _storage.write(
    key: 'push.$user',
    value: jsonEncode({'enabled': value.enabled, 'sound': value.sound}),
  );
}
