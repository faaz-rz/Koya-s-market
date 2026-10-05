import 'package:supabase_flutter/supabase_flutter.dart';

/// Staff OTP verifiers expire with the tab, just like the staff session.
class EphemeralPkceStorage implements GotrueAsyncStorage {
  final _values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}
