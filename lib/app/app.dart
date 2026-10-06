import '../features/store/widgets/store_realtime_sync.dart';
import '../features/notifications/widgets/customer_order_alerts.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_environment.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/customer_backdrop.dart';
import '../core/widgets/network_status_banner.dart';
import '../features/store/data/supabase_store_repository.dart';
import '../features/store/providers/store_provider.dart';
import '../features/auth/data/auth_repository.dart';
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
            SupabaseStoreRepository.clearReadCache(Supabase.instance.client);
            // Remote revocation, expiry, or another-tab sign-out must remove
            // cached orders, addresses, profile data, and cart immediately.
            ref.read(storeProvider.notifier).logout();
            final deleted = AuthRepository.takeAccountDeleted(
              Supabase.instance.client,
            );
            ref
                .read(appRouterProvider)
                .go('/login?reason=${deleted ? 'account-deleted' : 'session'}');
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
      theme: AppTheme.customer,
      builder: (context, child) => NetworkStatusBanner(
        child: CustomerOrderAlerts(
          child: StoreRealtimeSync(
            child: CustomerBackdrop(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
      routerConfig: router,
    );
  }
}
