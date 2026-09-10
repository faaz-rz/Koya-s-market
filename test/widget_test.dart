import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/features/checkout/models/checkout_models.dart';
import 'package:koyas_supermarket/core/theme/app_colors.dart';
import 'package:koyas_supermarket/core/utils/product_grid_layout.dart';
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

    expect(
      find.text('Your neighbourhood supermarket,\nnow at your fingertips.'),
      findsOneWidget,
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Open admin demo'), findsNothing);
    expect(find.text('Store administration'), findsNothing);
  });

  testWidgets('customer can permanently delete a demo account', (tester) async {
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: KoyasApp()));
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer-tab-profile')));
    await tester.pumpAndSettle();

    final deleteAccount = find.byKey(const Key('profile-delete-account'));
    await tester.ensureVisible(deleteAccount);
    await tester.tap(deleteAccount);
    await tester.pumpAndSettle();

    final finalDelete = find.byKey(const Key('delete-account-final'));
    expect(tester.widget<FilledButton>(finalDelete).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('delete-account-confirmation')),
      'DELETE',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(finalDelete).onPressed, isNotNull);

    await tester.tap(finalDelete);
    await tester.pumpAndSettle();
    expect(find.text('Groceries made simple.'), findsOneWidget);
    expect(find.textContaining('Account deleted'), findsOneWidget);
  });

  testWidgets('bottom tabs replace content without overlapping pages', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: KoyasApp()));
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer-login')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('customer-tab-orders')));
    await tester.pump();
    expect(find.text('Your orders'), findsOneWidget);
    expect(
      find.text('Your neighbourhood supermarket,\nnow at your fingertips.'),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('customer-tab-home')));
    await tester.pump();
    expect(
      find.text('Your neighbourhood supermarket,\nnow at your fingertips.'),
      findsOneWidget,
    );
    expect(find.text('Your orders'), findsNothing);
  });

  testWidgets('active cart ribbon opens cart and Add more returns home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.25;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const ProviderScope(child: KoyasApp()));
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('customer-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer-login')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final product = container
        .read(storeProvider)
        .products
        .firstWhere((item) => item.billingName == 'A ATTA MULTI 5KG');
    container.read(storeProvider.notifier).addToCart(product.id);
    await tester.pumpAndSettle();

    final ribbon = find.byKey(const ValueKey('active-cart-ribbon'));
    expect(ribbon, findsOneWidget);
    expect(find.text('1 item in cart'), findsOneWidget);
    expect(find.text('View cart'), findsOneWidget);
    expect(
      tester.getBottomLeft(ribbon).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(NavigationBar)).dy),
    );

    await tester.tap(find.byKey(const Key('view-active-cart')));
    await tester.pumpAndSettle();
    expect(find.text('Your cart'), findsOneWidget);
    expect(find.byKey(const Key('cart-add-more-items')), findsOneWidget);
    expect(ribbon, findsNothing);

    await tester.ensureVisible(find.byKey(const Key('cart-add-more-items')));
    await tester.tap(find.byKey(const Key('cart-add-more-items')));
    await tester.pumpAndSettle();

    expect(
      find.text('Your neighbourhood supermarket,\nnow at your fingertips.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('customer-tab-home')), findsOneWidget);
    expect(ribbon, findsOneWidget);
    expect(container.read(storeProvider).cartCount, 1);

    container.read(storeProvider.notifier).removeFromCart(product.id);
    await tester.pumpAndSettle();
    expect(ribbon, findsNothing);
  });

  testWidgets('search stays visible with active cart and iOS keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(const ProviderScope(child: KoyasApp()));
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer-login')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final products = container.read(storeProvider).products.take(2);
    for (final product in products) {
      container.read(storeProvider.notifier).addToCart(product.id);
    }
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();

    final search = find.byKey(const Key('product-search'));
    final ribbon = find.byKey(const ValueKey('active-cart-ribbon'));
    expect(search, findsOneWidget);
    expect(tester.getSize(search).width, greaterThan(280));
    expect(
      tester.getBottomLeft(search).dy,
      lessThan(tester.getTopLeft(ribbon).dy),
    );

    await tester.enterText(search, 'milk');
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('search-suggestions')), findsOneWidget);
    expect(find.textContaining('Search for "milk"'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('orders have no minimum until staff configures one', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(storeProvider.notifier);

    expect(container.read(storeProvider).minimumOrderPaise, 0);
    controller.loginDemo();
    controller.addToCart(productId(container, 'PEDA COLOUR'));
    expect(controller.placeOrder, returnsNormally);
  });

  test('cart enforces the admin minimum and available stock', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(storeProvider.notifier);

    controller.loginDemo(email: 'staff@koyas.in', isAdmin: true);
    controller.adminUpdateOrderPricing(
      minimumOrderPaise: 19900,
      deliveryChargePaise: 4900,
      freeDeliveryThresholdPaise: 79900,
    );
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

  testWidgets('phone product grid always fits three complete product cards', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const widths = <double>[320, 360, 412, 480, 599];
    const products = <Product>[
      Product(
        id: 'responsive-1',
        categoryId: 'category-test',
        name: 'Very Long Premium Basmati Rice Family Pack',
        description: 'Responsive grid test',
        unit: '5 kg family pack',
        pricePaise: 125500,
        stockQuantity: 5,
        visualKey: 'staples',
        brand: 'India Gate',
        subcategory: 'Rice',
      ),
      Product(
        id: 'responsive-2',
        categoryId: 'category-test',
        name: 'Medimix Ayurvedic Bathing Soap',
        description: 'Responsive grid test',
        unit: 'Pack of 4',
        pricePaise: 5400,
        stockQuantity: 5,
        visualKey: 'personal',
        brand: 'Medimix',
        subcategory: 'Bathing Soap',
      ),
      Product(
        id: 'responsive-3',
        categoryId: 'category-test',
        name: 'Stayfree Secure Sanitary Pads XL',
        description: 'Responsive grid test',
        unit: 'Pack of 37',
        pricePaise: 3700,
        stockQuantity: 5,
        visualKey: 'health',
        brand: 'Stayfree',
        subcategory: 'Personal Care',
      ),
    ];

    for (final width in widths) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(storeProvider.notifier);
      controller.loginDemo(isAdmin: true);
      for (final product in products) {
        controller.adminSaveProduct(product);
      }
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: const TextScaler.linear(1.3),
              ),
              child: Scaffold(
                body: LayoutBuilder(
                  builder: (context, constraints) => GridView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: products.length,
                    gridDelegate: ProductGridLayout.delegate(
                      context,
                      constraints.maxWidth - 40,
                    ),
                    itemBuilder: (context, index) =>
                        ProductCard(product: products[index]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 3, reason: 'width $width');
      expect(find.text('ADD'), findsNothing);
      for (final product in products) {
        final addButton = find.byKey(Key('add-product-${product.id}'));
        expect(addButton, findsOneWidget, reason: 'width $width');
        expect(
          tester.getSize(addButton),
          const Size.square(44),
          reason: 'width $width',
        );
      }
      await tester.tap(find.byKey(const Key('add-product-responsive-1')));
      await tester.pump();
      expect(
        find.byKey(const Key('quantity-product-responsive-1')),
        findsOneWidget,
        reason: 'width $width',
      );
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
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
    expect(
      find.text('Your neighbourhood supermarket,\nnow at your fingertips.'),
      findsOneWidget,
    );
  });

  testWidgets('customer applies a minimum-buy offer from the cart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: KoyasApp()));
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer-login')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final controller = container.read(storeProvider.notifier);
    for (final product in container.read(storeProvider).products) {
      if (product.isAvailable) controller.addToCart(product.id);
      if (container.read(storeProvider).subtotalPaise >= 50000) break;
    }
    expect(
      container.read(storeProvider).subtotalPaise,
      greaterThanOrEqualTo(50000),
    );
    container.read(appRouterProvider).go('/cart');
    await tester.pumpAndSettle();

    final chooseOffer = find.byKey(const Key('customer-choose-offer'));
    await tester.scrollUntilVisible(
      chooseOffer,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(chooseOffer);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('customer-offer-code')),
      'cart10',
    );
    await tester.tap(find.byKey(const Key('customer-apply-offer-code')));
    await tester.pumpAndSettle();

    final store = container.read(storeProvider);
    expect(store.selectedOfferCode, 'CART10');
    expect(store.offerDiscountPaise, greaterThan(0));
    expect(find.textContaining('You save'), findsOneWidget);
    expect(find.byKey(const Key('customer-remove-offer')), findsOneWidget);
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
