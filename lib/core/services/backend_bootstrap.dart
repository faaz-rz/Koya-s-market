import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import 'secure_auth_storage.dart';
import 'ephemeral_pkce_storage.dart';
import 'network_status.dart';

abstract final class BackendBootstrap {
  static Future<void> initialize({bool persistAuthSession = true}) async {
    if (!AppEnvironment.hasSupabaseConfig) return;
    await Supabase.initialize(
      url: AppEnvironment.supabaseUrl,
      publishableKey: AppEnvironment.supabaseAnonKey,
      httpClient: NetworkAwareClient(http.Client()),
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        localStorage: persistAuthSession
            ? const SecureAuthStorage()
            : const EmptyLocalStorage(),
        pkceAsyncStorage: persistAuthSession
            ? const SecureAuthStorage()
            : EphemeralPkceStorage(),
        detectSessionInUri: persistAuthSession,
      ),
    );
  }
}
