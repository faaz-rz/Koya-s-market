// Visual QA: flutter test --no-pub tool/customer_ui_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/features/products/product_variants.dart';
import 'package:koyas_supermarket/features/products/widgets/product_variant_sheet.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

class PreviewStore extends StoreController {
  void requireAddress() =>
      state = state.copyWith(addresses: [], selectedAddressId: '');
}

void main() {
  for (final viewport in [
    (width: 390.0, scale: 1.0, brightness: Brightness.light),
    (width: 320.0, scale: 2.0, brightness: Brightness.light),
    (width: 390.0, scale: 1.0, brightness: Brightness.dark),
    (width: 320.0, scale: 2.0, brightness: Brightness.dark),
  ]) {
    testWidgets('customer UI at ${viewport.width}px, text ${viewport.scale}', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final font = FontLoader('Manrope')
          ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await Future.wait([font.load(), icons.load()]);
      });
      tester.view.physicalSize = Size(viewport.width, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = viewport.scale;
      tester.platformDispatcher.platformBrightnessTestValue =
          viewport.brightness;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final container = ProviderContainer(
        overrides: [storeProvider.overrideWith(PreviewStore.new)],
      );
      addTearDown(container.dispose);
      final controller = container.read(storeProvider.notifier);
      controller.loginDemo();
      final router = container.read(appRouterProvider)..go('/home');
      const capture = Key('customer-ui-capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: UncontrolledProviderScope(
            container: container,
            child: const KoyasApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final prefix =
          '${viewport.width.toInt()}-${viewport.scale.toInt()}x'
          '${viewport.brightness == Brightness.dark ? '-dark' : ''}';
      await _capture(tester, capture, '$prefix-home');
      router.go('/categories');
      await tester.pumpAndSettle();
      await _capture(tester, capture, '$prefix-categories');

      final store = container.read(storeProvider);
      final product = store.products.firstWhere(
        (p) => p.billingName == 'A ATTA MULTI 5KG',
      );
      router.push('/products?category=${product.categoryId}');
      await tester.pumpAndSettle();
      await _capture(tester, capture, '$prefix-products');

      final family = ProductVariants.familyFor(
        product: product,
        catalogue: store.products,
      );
      router.push('/product/${product.id}');
      await tester.pumpAndSettle();
      await _capture(tester, capture, '$prefix-detail');
      router.pop();
      await tester.pumpAndSettle();
      showProductVariantSheet(
        context: tester.element(find.byKey(const Key('product-search'))),
        family: family,
      );
      await tester.pumpAndSettle();
      final selected = family.variants.firstWhere((p) => p.isAvailable);
      await tester.ensureVisible(find.byKey(Key('variant-add-${selected.id}')));
      await tester.tap(find.byKey(Key('variant-add-${selected.id}')));
      await tester.pumpAndSettle();
      await _capture(tester, capture, '$prefix-pack-picker');
      await tester.tap(find.byKey(const Key('confirm-variant-selection')));
      await tester.pumpAndSettle();

      for (final route in [
        (path: '/cart', name: 'cart'),
        (path: '/checkout/fulfilment', name: 'fulfilment'),
        (path: '/checkout/delivery', name: 'delivery'),
        (path: '/checkout/payment', name: 'payment'),
        (
          path: '/order/confirmation/${store.orders.first.id}',
          name: 'confirmed',
        ),
        (path: '/orders', name: 'orders'),
        (path: '/order/${store.orders.first.id}', name: 'order-details'),
        (path: '/profile', name: 'profile'),
      ]) {
        router.go(route.path);
        await tester.pumpAndSettle();
        await _capture(tester, capture, '$prefix-${route.name}');
      }
      controller.logout();
      router.go('/login');
      await tester.pumpAndSettle();
      await _capture(tester, capture, '$prefix-login');
      controller.loginDemo();
      (controller as PreviewStore).requireAddress();
      router.go('/address/setup');
      await tester.pumpAndSettle();
      await _capture(tester, capture, '$prefix-address-setup');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Future<void> _capture(WidgetTester tester, Key key, String name) async {
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(key));
    await Future.wait(
      tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => precacheImage(image.image, context)),
    );
  });
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/qa/customer-ui/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
  expect(tester.takeException(), isNull, reason: name);
}
