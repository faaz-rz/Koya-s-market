import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'push_configuration.dart';

abstract final class AppEnvironment {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');
  static const _accountDeletionUrl = String.fromEnvironment(
    'ACCOUNT_DELETION_URL',
  );

  // The web bundle includes these pages. Resolving against its HTTPS origin
  // lets Pages deployments use their assigned hostname without a placeholder.
  // Native releases still require explicit, published legal URLs.
  static String get privacyPolicyUrl =>
      _legalUrl(_privacyPolicyUrl, '/privacy');
  static String get accountDeletionUrl =>
      _legalUrl(_accountDeletionUrl, '/delete-account');

  static String _legalUrl(String configured, String path) =>
      configured.isNotEmpty
      ? configured
      : kIsWeb && Uri.base.isScheme('https')
      ? Uri.base.resolve(path).toString()
      : '';

  /// Native push is activated only with public Firebase build configuration,
  /// a configured server dispatcher and the required APNs provisioning.
  static const enablePushNotifications = PushConfiguration.enabled;

  /// Native online checkout is deliberately excluded from the first store
  /// release. Reintroducing it requires a separately audited payment SDK,
  /// privacy declarations, merchant configuration, and end-to-end testing.
  static const enableRazorpayPayments = false;
  static const enablePlayReviewLogin = bool.fromEnvironment(
    'ENABLE_PLAY_REVIEW_LOGIN',
  );
  static const adminIdleTimeoutMinutes = int.fromEnvironment(
    'ADMIN_IDLE_TIMEOUT_MINUTES',
    defaultValue: 15,
  );
  static const enableAdminDemo = bool.fromEnvironment('ENABLE_ADMIN_DEMO');

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasLegalUrls =>
      isHttpsUrl(privacyPolicyUrl) && isHttpsUrl(accountDeletionUrl);

  static bool isHttpsUrl(String value) {
    final uri = Uri.tryParse(value);
    return value == value.trim() &&
        uri != null &&
        uri.isScheme('https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.host.contains('_');
  }

  /// Frontend builds accept publishable keys or legacy JWTs with the anon
  /// role. This is a configuration check; Supabase verifies the key itself.
  static bool isPublicSupabaseKey(String key) {
    if (RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(key)) return true;
    try {
      final parts = key.split('.');
      if (parts.length != 3) return false;
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return claims is Map && claims['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }

  /// Sample customer data is a development convenience only. Unlike the
  /// separately opt-in admin preview, it can never be enabled in a release.
  static bool get allowCustomerDemo => !kReleaseMode && !hasSupabaseConfig;

  static bool get hasProductionCustomerConfig =>
      hasSupabaseConfig &&
      isHttpsUrl(supabaseUrl) &&
      isPublicSupabaseKey(supabaseAnonKey) &&
      hasLegalUrls;

  /// Release builds stay locked unless a client-evaluation build explicitly
  /// opts into sample data. Production deployments must never set this flag.
  static bool get allowAdminDemo =>
      !hasSupabaseConfig && (!kReleaseMode || enableAdminDemo);

  static Duration get adminIdleTimeout =>
      Duration(minutes: adminIdleTimeoutMinutes.clamp(5, 60));
}
