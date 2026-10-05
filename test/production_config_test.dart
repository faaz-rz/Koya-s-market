import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/core/config/app_environment.dart';

void main() {
  test(
    'frontend accepts publishable and anon keys and rejects privileged keys',
    () {
      String jwt(String role) =>
          'header.${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.signature';
      expect(
        AppEnvironment.isPublicSupabaseKey('sb_publishable_example123'),
        isTrue,
      );
      expect(AppEnvironment.isPublicSupabaseKey(jwt('anon')), isTrue);
      for (final key in [
        'sb_secret_example123',
        jwt('service_role'),
        'YOUR_SUPABASE_PUBLISHABLE_KEY',
        'malformed',
        '',
      ]) {
        expect(AppEnvironment.isPublicSupabaseKey(key), isFalse);
      }
    },
  );
  test('production URLs require HTTPS, a host and no embedded credentials', () {
    expect(AppEnvironment.isHttpsUrl('https://store.supabase.co'), isTrue);
    expect(AppEnvironment.isHttpsUrl('https://store.example/privacy'), isTrue);
    for (final url in [
      'http://store.example',
      'https:',
      'https:///privacy',
      'https://user:password@store.example',
      'https://YOUR_PROJECT.supabase.co',
      ' https://store.example',
    ]) {
      expect(AppEnvironment.isHttpsUrl(url), isFalse);
    }
  });
}
