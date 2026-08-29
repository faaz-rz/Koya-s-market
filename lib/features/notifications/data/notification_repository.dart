import 'package:supabase_flutter/supabase_flutter.dart';

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
