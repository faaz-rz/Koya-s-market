import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

/// Reserved RPC-only token persistence for the later push-notification release.
///
/// Keeping this boundary in source lets the server security policy stay tested
/// without shipping a Firebase SDK or registering a device in this release.
class NotificationRepository {
  NotificationRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    if (_client.auth.currentUser == null) return;
    await _client.rpc(
      'register_device_token',
      params: {'requested_token': token, 'requested_platform': platform},
    );
  }

  Future<void> unregisterDeviceToken(String token) => _client.rpc(
    'unregister_device_token',
    params: {'requested_token': token},
  );
}

abstract class PushDeviceRegistry {
  Future<bool> register(String user, String token, bool sound);
  Future<void> unregister(String user, String token);
}

final pushDeviceRegistryProvider = Provider<PushDeviceRegistry>(
  (ref) => SupabasePushDeviceRegistry(),
);

class SupabasePushDeviceRegistry implements PushDeviceRegistry {
  SupabaseClient get _client => Supabase.instance.client;
  @override
  Future<bool> register(String user, String token, bool sound) async {
    if (_client.auth.currentUser?.id != user) return false;
    final ready = await _client
        .rpc(
          'register_push_device',
          params: {
            'requested_token': token,
            'requested_platform': defaultTargetPlatform == TargetPlatform.iOS
                ? 'ios'
                : 'android',
            'requested_sound_enabled': sound,
          },
        )
        .timeout(const Duration(seconds: 8));
    return ready == true;
  }

  @override
  Future<void> unregister(String user, String token) async {
    if (_client.auth.currentUser?.id != user) return;
    await _client
        .rpc('unregister_device_token', params: {'requested_token': token})
        .timeout(const Duration(seconds: 5));
  }
}
