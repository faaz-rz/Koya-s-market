import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

void main() {
  testWidgets('customer shopping actions have labeled Android touch targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
      UncontrolledProviderScope(container: container, child: const KoyasApp()),
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
  });
}
