import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/store/providers/store_provider.dart';
import '../screens/admin_login_screen.dart';
import '../screens/admin_splash_screen.dart';
import '../widgets/admin_session_guard.dart';
import '../../features/store/widgets/store_realtime_sync.dart';

final adminRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final location = state.uri.path;
      final store = ref.read(storeProvider);
      final publicRoute = location == '/splash' || location == '/login';
      final hasStaffAccess =
          store.isAuthenticated && store.isAdminAccount && store.isAdminView;
      if (!hasStaffAccess && !publicRoute) return '/login';
      if (hasStaffAccess && location == '/login') return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const AdminSplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final reason = state.uri.queryParameters['reason'];
          return AdminLoginScreen(
            accessDenied: reason == 'unauthorized',
            sessionExpired: reason == 'expired',
          );
        },
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AdminSessionGuard(child: StoreRealtimeSync(child: child)),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const AdminDashboardScreen(
              section: AdminSection.overview,
              manageLiveSync: false,
            ),
          ),
          GoRoute(
            path: '/analytics',
            builder: (context, state) => const AdminDashboardScreen(
              section: AdminSection.analytics,
              manageLiveSync: false,
            ),
          ),
          GoRoute(
            path: '/pricing',
            builder: (context, state) => const AdminDashboardScreen(
              section: AdminSection.pricing,
              manageLiveSync: false,
            ),
          ),
          GoRoute(
            path: '/orders',
            builder: (context, state) => AdminDashboardScreen(
              section: AdminSection.orders,
              manageLiveSync: false,
              orderFocusKey: state.uri.queryParameters['focus'],
            ),
          ),
          GoRoute(
            path: '/inventory',
            builder: (context, state) => const AdminDashboardScreen(
              section: AdminSection.inventory,
              manageLiveSync: false,
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => context.go('/dashboard'),
          child: const Text('Return to dashboard'),
        ),
      ),
    ),
  );
  ref.listen(
    storeProvider.select(
      (store) =>
          (store.isAuthenticated, store.isAdminAccount, store.isAdminView),
    ),
    (_, _) => router.refresh(),
  );
  ref.onDispose(router.dispose);
  return router;
});
