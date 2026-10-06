/// Registered by the customer app only. Staff authentication does not create
/// a Firebase instance. Cleanup runs before the Supabase credential is removed.
abstract final class PushSessionLifecycle {
  static Future<void> Function()? beforeSignOut;
}
