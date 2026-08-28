import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_environment.dart';
import '../core/theme/app_theme.dart';
import '../features/store/providers/store_provider.dart';
import 'router/app_router.dart';

class KoyasApp extends ConsumerStatefulWidget {
  const KoyasApp({super.key});

  @override
  ConsumerState<KoyasApp> createState() => _KoyasAppState();
}

class _KoyasAppState extends ConsumerState<KoyasApp> {
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    if (AppEnvironment.hasSupabaseConfig) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            if (state.session != null || !mounted) return;
            // Remote revocation, expiry, or another-tab sign-out must remove
            // cached orders, addresses, profile data, and cart immediately.
            ref.read(storeProvider.notifier).logout();
            ref.read(appRouterProvider).go('/login?reason=session');
          });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Koya Stores',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
