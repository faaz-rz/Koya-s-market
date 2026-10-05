import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/admin/admin_app.dart';
import 'package:koyas_supermarket/admin/router/admin_router.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

void main() {
  testWidgets(
    'customer private deep links require sign-in and logout redirects immediately',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider)..go('/login');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const KoyasApp(),
        ),
      );
      await tester.pumpAndSettle();
      for (final route in [
        '/home',
        '/categories',
        '/orders',
        '/profile',
        '/products',
        '/product/unknown',
        '/cart',
        '/checkout/fulfilment',
        '/checkout/delivery',
        '/checkout/payment',
        '/order/unknown',
      ]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/login',
          reason: route,
        );
      }
      container.read(storeProvider.notifier).loginDemo();
      router.go('/profile');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/profile');
      container.read(storeProvider.notifier).logout();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/login');
      expect(container.read(storeProvider).profile, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'staff routes reject customers and redirect when staff access ends',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = container.read(adminRouterProvider)..go('/login');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const KoyasAdminApp(),
        ),
      );
      await tester.pumpAndSettle();
      container.read(storeProvider.notifier).loginDemo();
      for (final route in [
        '/dashboard',
        '/analytics',
        '/pricing',
        '/orders',
        '/inventory',
      ]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/login',
          reason: route,
        );
      }
      container.read(storeProvider.notifier).loginDemo(isAdmin: true);
      router.go('/dashboard');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/dashboard');
      container.read(storeProvider.notifier).setAdminView(false);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/login');
      container.read(storeProvider.notifier).logout();
      await tester.pumpAndSettle();
      router.go('/orders');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/login');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
