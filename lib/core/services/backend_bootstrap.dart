import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_environment.dart';

abstract final class BackendBootstrap {
  static Future<void> initialize({bool persistAuthSession = true}) async {
    if (!AppEnvironment.hasSupabaseConfig) return;
    await Supabase.initialize(
      url: AppEnvironment.supabaseUrl,
      publishableKey: AppEnvironment.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        localStorage: persistAuthSession ? null : const EmptyLocalStorage(),
        detectSessionInUri: persistAuthSession,
      ),
    );
    if (AppEnvironment.enablePushNotifications) {
      await Firebase.initializeApp();
    }
  }
}
