import 'package:flutter/foundation.dart';

abstract final class AppEnvironment {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');
  static const accountDeletionUrl = String.fromEnvironment(
    'ACCOUNT_DELETION_URL',
  );

  /// Push notifications are deliberately excluded from the first store
  /// release. A later release must add audited SDKs, APNs/FCM credentials,
  /// platform capabilities, privacy declarations and physical-device tests.
  static const enablePushNotifications = false;

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
      Uri.tryParse(privacyPolicyUrl)?.isScheme('https') == true &&
      Uri.tryParse(accountDeletionUrl)?.isScheme('https') == true;

  /// Sample customer data is a development convenience only. Unlike the
  /// separately opt-in admin preview, it can never be enabled in a release.
  static bool get allowCustomerDemo => !kReleaseMode && !hasSupabaseConfig;

  static bool get hasProductionCustomerConfig =>
      hasSupabaseConfig && supabaseUrl.startsWith('https://');

  /// Release builds stay locked unless a client-evaluation build explicitly
  /// opts into sample data. Production deployments must never set this flag.
  static bool get allowAdminDemo =>
      !hasSupabaseConfig && (!kReleaseMode || enableAdminDemo);

  static Duration get adminIdleTimeout =>
      Duration(minutes: adminIdleTimeoutMinutes.clamp(5, 60));
}
