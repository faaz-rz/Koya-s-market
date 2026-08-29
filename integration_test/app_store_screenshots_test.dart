import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/features/checkout/models/checkout_models.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';
import 'package:koyas_supermarket/main.dart' as app;

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pumpAndSettle();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture App Store customer journey', (tester) async {
    await app.main();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 900)),
    );
    await _settle(tester);

    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await _settle(tester);
    }

    await tester.tap(find.byKey(const Key('customer-login')));
    await _settle(tester);

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final router = container.read(appRouterProvider);
    final controller = container.read(storeProvider.notifier);

    await binding.takeScreenshot('screenshot-01-home');

    router.go('/categories');
    await _settle(tester);
    await binding.takeScreenshot('screenshot-02-categories');

    final featuredProduct = container
        .read(storeProvider)
        .products
        .firstWhere((product) => product.isAvailable && product.featured);
    router.go('/product/${featuredProduct.id}');
    await _settle(tester);
    await binding.takeScreenshot('screenshot-03-product');

    for (final product in container.read(storeProvider).products) {
      while (container.read(storeProvider).subtotalPaise < 50000 &&
          product.isAvailable &&
          (container.read(storeProvider).cartQuantities[product.id] ?? 0) <
              product.stockQuantity) {
        controller.addToCart(product.id);
      }
      if (container.read(storeProvider).subtotalPaise >= 50000) break;
    }
    controller.applyOffer('CART10');
    router.go('/cart');
    await _settle(tester);
    await binding.takeScreenshot('screenshot-04-offer-cart');

    controller.setFulfilment(FulfilmentType.delivery);
    router.go('/checkout/delivery');
    await _settle(tester);
    await binding.takeScreenshot('screenshot-05-delivery');

    router.go('/profile');
    await _settle(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('profile-delete-account')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await _settle(tester);
    await binding.takeScreenshot('screenshot-06-profile-privacy');

    expect(tester.takeException(), isNull);
  });
}
