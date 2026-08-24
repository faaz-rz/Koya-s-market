import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/customer_shell.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/cart/screens/cart_screen.dart';
import '../../features/checkout/screens/delivery_checkout_screen.dart';
import '../../features/checkout/screens/fulfilment_screen.dart';
import '../../features/checkout/screens/payment_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/orders/screens/order_confirmation_screen.dart';
import '../../features/orders/screens/order_history_screen.dart';
import '../../features/orders/screens/order_details_screen.dart';
import '../../features/products/screens/categories_screen.dart';
import '../../features/products/screens/product_detail_screen.dart';
import '../../features/products/screens/product_listing_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/store/providers/store_provider.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final location = state.uri.path;
      final store = ref.read(storeProvider);
      final publicRoute = location == '/splash' || location == '/login';
      if (!store.isAuthenticated && !publicRoute) return '/login';
      if (store.isAuthenticated && location == '/login') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            CustomerShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/categories',
            builder: (context, state) => const CategoriesScreen(),
          ),
          GoRoute(
            path: '/orders',
            builder: (context, state) => const OrderHistoryScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/products',
        builder: (context, state) => ProductListingScreen(
          categoryId: state.uri.queryParameters['category'],
        ),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) =>
            ProductDetailScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
      GoRoute(
        path: '/checkout/fulfilment',
        builder: (context, state) => const FulfilmentScreen(),
      ),
      GoRoute(
        path: '/checkout/pickup',
        redirect: (context, state) => '/checkout/payment',
      ),
      GoRoute(
        path: '/checkout/delivery',
        builder: (context, state) => const DeliveryCheckoutScreen(),
      ),
      GoRoute(
        path: '/checkout/payment',
        builder: (context, state) => const PaymentScreen(),
      ),
      GoRoute(
        path: '/order/confirmation/:id',
        builder: (context, state) =>
            OrderConfirmationScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/order/:id',
        builder: (context, state) =>
            OrderDetailsScreen(orderId: state.pathParameters['id']!),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => context.go('/home'),
          child: const Text('Return home'),
        ),
      ),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});
