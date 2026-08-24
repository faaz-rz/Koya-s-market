import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationRepository {
  NotificationRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('device_tokens').upsert({
      'user_id': user.id,
      'token': token,
      'platform': platform,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }

  Future<void> unregisterDeviceToken(String token) =>
      _client.from('device_tokens').delete().eq('token', token);
}
