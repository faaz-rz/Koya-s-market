import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'customer shopping actions have labeled Android touch targets in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final semantics = tester.ensureSemantics();
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final controller = container.read(storeProvider.notifier)..loginDemo();
        final product = container
            .read(storeProvider)
            .products
            .firstWhere((product) => product.isAvailable);
        controller.addToCart(product.id);
        final router = container.read(appRouterProvider);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const KoyasApp(),
          ),
        );
        try {
          for (final route in [
            '/home',
            '/products?category=${product.categoryId}',
            '/product/${product.id}',
            '/cart',
            '/checkout/fulfilment',
            '/profile',
          ]) {
            router.go(route);
            await tester.pumpAndSettle();
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
              reason: route,
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
              reason: route,
            );
            expect(tester.takeException(), isNull, reason: route);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
