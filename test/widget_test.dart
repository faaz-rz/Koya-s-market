import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/features/checkout/models/checkout_models.dart';
import 'package:koyas_supermarket/core/theme/app_colors.dart';
import 'package:koyas_supermarket/features/orders/models/order.dart';
import 'package:koyas_supermarket/features/products/models/product.dart';
import 'package:koyas_supermarket/features/products/widgets/product_card.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

void main() {
  String productId(ProviderContainer container, String billingName) => container
      .read(storeProvider)
      .products
      .firstWhere((product) => product.billingName == billingName)
      .id;

  testWidgets('customer can sign in and reach the storefront', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KoyasApp()));
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();

    expect(find.text('Groceries made simple.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('customer-login')));
    await tester.pumpAndSettle();

    expect(find.text('Fresh groceries,\nwithout the rush.'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Open admin demo'), findsNothing);
    expect(find.text('Store administration'), findsNothing);
  });

  test('cart validates minimum amount and stock', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(storeProvider.notifier);

    final lowPriceProductId = productId(container, 'PEDA COLOUR');
    final stock = container
        .read(storeProvider)
        .productById(lowPriceProductId)!
        .stockQuantity;
    controller.addToCart(lowPriceProductId);
    expect(controller.placeOrder, throwsA(isA<StoreValidationException>()));

    for (var index = 1; index < stock; index++) {
      controller.addToCart(lowPriceProductId);
    }
    expect(
      () => controller.addToCart(lowPriceProductId),
      throwsA(isA<StoreValidationException>()),
    );
  });

  test('placing an order revalidates and clears the cart', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(storeProvider.notifier);

    controller.loginDemo();
    final product = container
        .read(storeProvider)
        .products
        .firstWhere((item) => item.billingName == 'A ATTA MULTI 5KG');
    controller.addToCart(product.id);
    final orderId = controller.placeOrder();
    final state = container.read(storeProvider);

    expect(orderId, startsWith('KOY'));
    expect(state.cartItems, isEmpty);
    expect(state.orders.first.status, OrderStatus.placed);
    expect(
      state.productById(product.id)?.stockQuantity,
      product.stockQuantity - 1,
    );
  });

  test('eligible cancellation restores reserved stock', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(storeProvider.notifier);

    controller.loginDemo();
    final product = container
        .read(storeProvider)
        .products
        .firstWhere((item) => item.billingName == 'A ATTA MULTI 5KG');
    controller.addToCart(product.id);
    final orderId = controller.placeOrder();
    expect(
      container.read(storeProvider).productById(product.id)?.stockQuantity,
      product.stockQuantity - 1,
    );

    controller.cancelOrder(orderId);
    final state = container.read(storeProvider);
    expect(state.orders.first.status, OrderStatus.cancelled);
    expect(state.productById(product.id)?.stockQuantity, product.stockQuantity);
  });

  test('admin view cannot be enabled for an unauthenticated user', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      () => container.read(storeProvider.notifier).setAdminView(true),
      throwsA(isA<StoreValidationException>()),
    );
  });

  test('admin stock updates affect only the selected product', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(storeProvider.notifier);
    controller.loginDemo();
    controller.setAdminView(true);

    final before = container.read(storeProvider);
    final selected = before.products.firstWhere(
      (item) => item.billingName == 'DOVE RS 58',
    );
    final untouched = before.products.firstWhere(
      (item) => item.billingName == 'PEDA COLOUR',
    );
    controller.adminSaveProduct(selected.copyWith(stockQuantity: 50));
    final after = container.read(storeProvider);

    expect(after.productById(selected.id)?.stockQuantity, 50);
    expect(
      after.productById(untouched.id)?.stockQuantity,
      untouched.stockQuantity,
    );
  });

  test(
    'online payments cannot be selected in the first production release',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(storeProvider.notifier);

      expect(
        () => controller.setPaymentMethod(PaymentMethod.online),
        throwsA(isA<StoreValidationException>()),
      );
    },
  );

  testWidgets('delivery checkout offers cash or UPI on delivery', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: KoyasApp()));
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer-login')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final controller = container.read(storeProvider.notifier);
    controller.addToCart(productId(container, 'A ATTA MULTI 5KG'));
    controller.setFulfilment(FulfilmentType.delivery);
    container.read(appRouterProvider).go('/checkout/payment');
    await tester.pumpAndSettle();

    expect(find.text('Cash or UPI on delivery'), findsOneWidget);
    expect(
      find.text('Pay by cash or UPI when your order is delivered.'),
      findsOneWidget,
    );
    expect(find.text('UPI, card, or net banking'), findsNothing);
    expect(find.textContaining('Razorpay'), findsNothing);
  });

  testWidgets('uses the approved accessible brand color', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KoyasApp()));
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).colorScheme.primary, AppColors.brand600);
    expect(Theme.of(context).useMaterial3, isTrue);
  });

  testWidgets('product card exposes the complete brand and item name', (
    tester,
  ) async {
    const name = "Johnson's Baby Lotion 200 ml";
    const brand = "Johnson's";
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 230,
              height: 380,
              child: ProductCard(
                product: Product(
                  id: 'display-test',
                  categoryId: 'category-test',
                  name: name,
                  description: 'Display test',
                  unit: 'Pack of 50',
                  pricePaise: 1000,
                  stockQuantity: 5,
                  visualKey: 'pooja',
                  brand: brand,
                  subcategory: 'Pooja Supplies',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(name), findsOneWidget);
    expect(find.text(brand), findsOneWidget);
    expect(tester.widget<Text>(find.text(name)).maxLines, 3);
    expect(tester.widget<Text>(find.text(brand)).maxLines, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('order details omit tracking and provide a route home', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: KoyasApp()));
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer-login')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final controller = container.read(storeProvider.notifier);
    controller.addToCart(productId(container, 'A ATTA MULTI 5KG'));
    final orderId = controller.placeOrder();
    container.read(appRouterProvider).go('/order/$orderId');
    await tester.pumpAndSettle();

    expect(find.text('Back to home'), findsOneWidget);
    expect(find.byTooltip('Go to home'), findsOneWidget);
    expect(find.text('Order received'), findsOneWidget);
    expect(find.text('Order progress'), findsNothing);
    expect(
      find.text('We will notify you when it is ready for pickup'),
      findsOneWidget,
    );
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getCenter(find.text('Back to home')).dy,
      greaterThan(screenHeight * 0.75),
    );

    await tester.tap(find.text('Back to home'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh groceries,\nwithout the rush.'), findsOneWidget);
  });

  testWidgets('pickup checkout skips date and time selection', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KoyasApp()));
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer-login')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    container
        .read(storeProvider.notifier)
        .addToCart(productId(container, 'A ATTA MULTI 5KG'));
    container.read(appRouterProvider).go('/checkout/pickup');
    await tester.pumpAndSettle();

    expect(find.text('Review and pay'), findsOneWidget);
    expect(find.text('Payment method'), findsOneWidget);
    expect(find.text('Cash or UPI at pickup'), findsOneWidget);
    expect(find.text('Pickup day'), findsNothing);
    expect(find.text('When would you like to collect?'), findsNothing);
    expect(find.text('Schedule'), findsNothing);
    expect(find.textContaining('Pickup window'), findsNothing);
    expect(find.textContaining('9:00 AM'), findsNothing);
    expect(find.textContaining('11:00 AM'), findsNothing);
    expect(
      find.text('We will notify you when your order is ready'),
      findsOneWidget,
    );
  });

  test('pickup orders advance directly to ready for pickup', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(storeProvider.notifier);

    controller.loginDemo();
    controller.addToCart(productId(container, 'A ATTA MULTI 5KG'));
    final orderId = controller.placeOrder();
    controller.advanceOrder(orderId);

    final order = container
        .read(storeProvider)
        .orders
        .firstWhere((item) => item.id == orderId);
    expect(order.status, OrderStatus.readyForPickup);
  });
}
