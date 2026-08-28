import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase refresh session and PKCE verifier outside plain native
/// preferences. Native builds use Keychain/Keystore-backed encrypted storage;
/// web builds use WebCrypto-backed session storage and expire with the tab.
class SecureAuthStorage extends LocalStorage implements GotrueAsyncStorage {
  const SecureAuthStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(
        resetOnError: true,
        migrateWithBackup: false,
        storageNamespace: 'koyas_auth',
      ),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
        synchronizable: false,
      ),
      webOptions: WebOptions(
        publicKey: 'KoyasSecureSession',
        useSessionStorage: true,
      ),
    ),
  }) : _storage = storage;

  static const _sessionKey = 'supabase.auth.session';
  static const _pkcePrefix = 'supabase.auth.pkce.';

  final FlutterSecureStorage _storage;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async =>
      (await _storage.read(key: _sessionKey)) != null;

  @override
  Future<String?> accessToken() => _storage.read(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _sessionKey, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _sessionKey);

  @override
  Future<String?> getItem({required String key}) =>
      _storage.read(key: '$_pkcePrefix$key');

  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: '$_pkcePrefix$key', value: value);

  @override
  Future<void> removeItem({required String key}) =>
      _storage.delete(key: '$_pkcePrefix$key');
}
