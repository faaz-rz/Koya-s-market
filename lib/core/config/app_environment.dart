import 'package:flutter/foundation.dart';

abstract final class AppEnvironment {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const enablePushNotifications = bool.fromEnvironment(
    'ENABLE_PUSH_NOTIFICATIONS',
  );
  static const enableRazorpayPayments = bool.fromEnvironment(
    'ENABLE_RAZORPAY_PAYMENTS',
  );
  static const adminIdleTimeoutMinutes = int.fromEnvironment(
    'ADMIN_IDLE_TIMEOUT_MINUTES',
    defaultValue: 15,
  );

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Demo access is deliberately unavailable in release builds so a missing
  /// production configuration can never expose a fake staff dashboard.
  static bool get allowAdminDemo => !kReleaseMode && !hasSupabaseConfig;

  static Duration get adminIdleTimeout =>
      Duration(minutes: adminIdleTimeoutMinutes.clamp(5, 60));
}
