import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_environment.dart';
import 'secure_auth_storage.dart';

abstract final class BackendBootstrap {
  static Future<void> initialize({bool persistAuthSession = true}) async {
    if (!AppEnvironment.hasSupabaseConfig) return;
    await Supabase.initialize(
      url: AppEnvironment.supabaseUrl,
      publishableKey: AppEnvironment.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        localStorage: persistAuthSession
            ? const SecureAuthStorage()
            : const EmptyLocalStorage(),
        pkceAsyncStorage: persistAuthSession ? const SecureAuthStorage() : null,
        detectSessionInUri: persistAuthSession,
      ),
    );
  }
}
