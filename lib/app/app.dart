import '../features/store/widgets/store_realtime_sync.dart';
import '../features/cart/providers/cart_persistence.dart';
import '../features/notifications/providers/push_session.dart';
import '../features/notifications/services/push_session_lifecycle.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(cartPersistenceProvider);
      final push = ref.read(pushSessionProvider);
      PushSessionLifecycle.beforeSignOut = push.beforeSignOut;
      push.onMessage = (data) => unawaited(_pushRefresh(data));
      push.onOpen = (data) => unawaited(_pushRefresh(data, open: true));
    });
    if (AppEnvironment.hasSupabaseConfig) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            if (state.session != null || !mounted) return;
            SupabaseStoreRepository.clearReadCache(Supabase.instance.client);
            // Remote revocation, expiry, or another-tab sign-out must remove
            // cached orders, addresses, profile data, and cart immediately.
            final previousCustomer = ref.read(storeProvider).profile?.id;
            final deleted = AuthRepository.takeAccountDeleted(
              Supabase.instance.client,
            );
            ref.read(storeProvider.notifier).logout();
            if (deleted && previousCustomer != null) {
              unawaited(
                ref
                    .read(cartPersistenceProvider)
                    .deleteForAccount(previousCustomer)
                    .catchError((Object _) {}),
              );
            }
            ref
                .read(appRouterProvider)
                .go('/login?reason=${deleted ? 'account-deleted' : 'session'}');
          });
    }
  }

  @override
  void dispose() {
    PushSessionLifecycle.beforeSignOut = null;
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _pushRefresh(
    Map<String, dynamic> data, {
    bool open = false,
  }) async {
    final user = ref.read(storeProvider).profile?.id;
    if (!mounted ||
        user == null ||
        data['user_id'] != user ||
        !AppEnvironment.hasSupabaseConfig) {
      return;
    }
    try {
      final bundle = await SupabaseStoreRepository().loadStore();
      if (!mounted ||
          ref.read(storeProvider).profile?.id != user ||
          bundle.profile.id != user) {
        return;
      }
      ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
      if (open && bundle.orders.any((o) => o.id == data['order_id'])) {
        ref.read(appRouterProvider).go('/order/${data['order_id']}');
      }
    } catch (_) {
      // The existing network banner/retry flow remains available. Notification
      // data never creates an order or bypasses the owned database read.
      if (mounted &&
          open &&
          ref.read(storeProvider).isAuthenticated &&
          ref.read(storeProvider).profile?.id == user) {
        ref.read(appRouterProvider).go('/orders');
      }
    }
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
