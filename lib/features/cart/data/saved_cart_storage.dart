import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/config/app_environment.dart';

abstract class SavedCartStorage {
  Future<Map<String, int>> read(String userId);
  Future<void> write(String userId, Map<String, int> quantities);
  Future<void> remove(String userId);
}

final savedCartStorageProvider = Provider<SavedCartStorage>(
  (ref) => AppEnvironment.allowCustomerDemo
      ? DemoCartStorage()
      : EncryptedCartStorage(),
);

class DemoCartStorage implements SavedCartStorage {
  final _carts = <String, Map<String, int>>{};
  @override
  Future<Map<String, int>> read(String user) async =>
      Map.of(_carts[user] ?? {});
  @override
  Future<void> write(String user, Map<String, int> quantities) async {
    _carts[user] = Map.of(quantities);
  }

  @override
  Future<void> remove(String user) async {
    _carts.remove(user);
  }
}

class EncryptedCartStorage implements SavedCartStorage {
  EncryptedCartStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              resetOnError: true,
              migrateWithBackup: false,
              storageNamespace: 'koyas_carts',
            ),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
              synchronizable: false,
            ),
            webOptions: WebOptions(
              publicKey: 'KoyasSavedCarts',
              useSessionStorage: false,
            ),
          );
  final FlutterSecureStorage _storage;
  String _key(String userId) => 'saved.cart.v1.$userId';
  static Map<String, int> decode(String? raw) {
    if (raw == null) return {};
    if (raw.length > 512 * 1024) return {};
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['version'] != 1 || data['items'] is! Map) {
        return {};
      }
      final items = data['items'] as Map;
      if (items.length > 5000) return {};
      return {
        for (final e in items.entries)
          if (e.key is String &&
              RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(e.key) &&
              e.value is int &&
              e.value > 0 &&
              e.value <= 999999)
            e.key as String: e.value as int,
      };
    } catch (_) {
      return {};
    }
  }

  @override
  Future<Map<String, int>> read(String userId) async =>
      decode(await _storage.read(key: _key(userId)));
  @override
  Future<void> write(String userId, Map<String, int> quantities) =>
      _storage.write(
        key: _key(userId),
        value: jsonEncode({'version': 1, 'items': quantities}),
      );
  @override
  Future<void> remove(String userId) => _storage.delete(key: _key(userId));
}
