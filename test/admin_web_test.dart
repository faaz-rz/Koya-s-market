import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/admin/admin_app.dart';
import 'package:koyas_supermarket/features/admin/printing/order_bill_printer.dart';
import 'package:koyas_supermarket/features/orders/models/order.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

void main() {
  testWidgets('staff website signs in separately and opens the dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: KoyasAdminApp()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Staff sign in'), findsOneWidget);
    expect(find.text('Open staff dashboard demo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const Key('admin-email')),
      'staff@koyas.in',
    );
    await tester.tap(find.byKey(const Key('admin-login')));
    await tester.pumpAndSettle();

    expect(find.text('Store dashboard'), findsOneWidget);
    expect(find.byKey(const Key('admin-session-guard')), findsOneWidget);
    expect(find.byKey(const Key('admin-bottom-navigation')), findsOneWidget);
    expect(find.text('Orders today'), findsOneWidget);
    expect(find.byKey(const Key('admin-sales-analytics')), findsNothing);
    expect(find.byKey(const Key('admin-category-inventory')), findsNothing);
    expect(find.byTooltip('Sign out'), findsOneWidget);
    expect(find.text('Customer app'), findsNothing);
  });

  testWidgets('admin filters inventory by category and adjusts stock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: KoyasAdminApp()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-email')),
      'staff@koyas.in',
    );
    await tester.tap(find.byKey(const Key('admin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-nav-inventory')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final state = container.read(storeProvider);
    final category = state.categories.first;
    final selectedProduct = state.products.firstWhere(
      (product) =>
          product.categoryId == category.id && product.brand.isNotEmpty,
    );
    final otherBrandProduct = state.products.firstWhere(
      (product) =>
          product.categoryId == category.id &&
          product.brand != selectedProduct.brand,
    );
    final otherProduct = state.products.firstWhere(
      (product) => product.categoryId != category.id,
    );
    final originalStock = selectedProduct.stockQuantity;

    final inventory = find.byKey(const Key('admin-category-inventory'));
    await tester.scrollUntilVisible(
      inventory,
      700,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(Key('admin-category-${category.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('admin-product-${otherProduct.id}')), findsNothing);

    await tester.tap(find.byKey(const Key('admin-brand-filter')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-brand-search')),
      selectedProduct.brand,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('admin-brand-option-${selectedProduct.brand}')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('admin-product-${selectedProduct.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('admin-product-${otherBrandProduct.id}')),
      findsNothing,
    );

    final increase = find.byKey(
      Key('admin-stock-increase-${selectedProduct.id}'),
    );
    await tester.ensureVisible(increase);
    await tester.tap(increase);
    await tester.pump();
    // The draft changes immediately; only Save writes inventory.
    expect(
      container
          .read(storeProvider)
          .productById(selectedProduct.id)
          ?.stockQuantity,
      originalStock,
    );
    await tester.tap(find.byKey(Key('admin-stock-save-${selectedProduct.id}')));
    await tester.pumpAndSettle();

    expect(
      container
          .read(storeProvider)
          .productById(selectedProduct.id)
          ?.stockQuantity,
      originalStock + 1,
    );
  });

  testWidgets('admin sets counted stock and filters inventory status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: KoyasAdminApp()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-email')),
      'staff@koyas.in',
    );
    await tester.tap(find.byKey(const Key('admin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-nav-inventory')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final product = container.read(storeProvider).products.first;
    final outOfStockProduct = container
        .read(storeProvider)
        .products
        .firstWhere((candidate) => candidate.id != product.id);
    container
        .read(storeProvider.notifier)
        .adminSaveProduct(outOfStockProduct.copyWith(stockQuantity: 0));
    await tester.pumpAndSettle();
    final inventory = find.byKey(const Key('admin-category-inventory'));
    await tester.scrollUntilVisible(
      inventory,
      700,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.enterText(
      find.byKey(const Key('admin-product-search')),
      product.name,
    );
    await tester.pumpAndSettle();
    final setStock = find.byKey(Key('admin-stock-set-${product.id}'));
    await tester.ensureVisible(setStock);
    await tester.tap(setStock);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('admin-stock-input')), '7');
    await tester.tap(find.text('Update stock'));
    await tester.pumpAndSettle();

    expect(
      container.read(storeProvider).productById(product.id)?.stockQuantity,
      7,
    );
    expect(find.text('${product.name} stock set to 7.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('admin-product-search')), '');
    await tester.pumpAndSettle();

    final lowStockFilter = find.byKey(
      const Key('admin-stock-filter-low-stock'),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
    await tester.pumpAndSettle();
    await tester.ensureVisible(lowStockFilter);
    await tester.tap(lowStockFilter);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(lowStockFilter).selected, isTrue);
    expect(find.byKey(Key('admin-product-${product.id}')), findsOneWidget);

    final outOfStockFilter = find.byKey(
      const Key('admin-stock-filter-out-of-stock'),
    );
    await tester.tap(find.byKey(const Key('admin-all-products-summary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-out-of-stock-summary')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(outOfStockFilter).selected, isTrue);
    expect(find.byKey(Key('admin-product-${product.id}')), findsNothing);
    final firstOutOfStock =
        container
            .read(storeProvider)
            .products
            .where((candidate) => candidate.stockQuantity == 0)
            .toList()
          ..sort((first, second) {
            final brand = first.brand.toLowerCase().compareTo(
              second.brand.toLowerCase(),
            );
            return brand != 0
                ? brand
                : first.name.toLowerCase().compareTo(second.name.toLowerCase());
          });
    expect(
      find.byKey(Key('admin-product-${firstOutOfStock.first.id}')),
      findsOneWidget,
    );
  });

  testWidgets('admin can open a new product form with picture upload', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: KoyasAdminApp()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-email')),
      'staff@koyas.in',
    );
    await tester.tap(find.byKey(const Key('admin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-nav-inventory')));
    await tester.pumpAndSettle();

    final addProduct = find.byKey(const Key('admin-add-product'));
    await tester.scrollUntilVisible(
      addProduct,
      700,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(addProduct);
    await tester.pumpAndSettle();

    expect(find.text('Add product'), findsWidgets);
    expect(
      find.byKey(const Key('admin-product-image-preview')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin-pick-product-image')), findsOneWidget);
    expect(find.text('Add picture'), findsOneWidget);
    expect(find.text('Storefront product name'), findsOneWidget);
    expect(find.text('Stock quantity'), findsOneWidget);
    expect(
      find.byKey(const Key('admin-advanced-product-details')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin-product-active')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('admin-product-name')),
      'Koya Test Product',
    );
    await tester.enterText(
      find.byKey(const Key('admin-product-description')),
      'A product created by the catalogue manager test.',
    );
    await tester.enterText(
      find.byKey(const Key('admin-product-price')),
      '49.00',
    );
    await tester.tap(find.byKey(const Key('admin-save-product')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final saved = container
        .read(storeProvider)
        .products
        .firstWhere((product) => product.name == 'Koya Test Product');
    expect(saved.pricePaise, 4900);
    expect(saved.active, isTrue);
    expect(saved.billingName, 'Koya Test Product');
  });

  testWidgets('admin can archive and restore a product safely', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: KoyasAdminApp()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-email')),
      'staff@koyas.in',
    );
    await tester.tap(find.byKey(const Key('admin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-nav-inventory')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final product = container.read(storeProvider).products.first;
    final search = find.byKey(const Key('admin-product-search'));
    await tester.scrollUntilVisible(
      search,
      600,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(search, product.name);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('admin-product-actions-${product.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit product'));
    await tester.pumpAndSettle();
    final renamedProduct = '${product.name} Updated';
    await tester.enterText(
      find.byKey(const Key('admin-product-name')),
      renamedProduct,
    );
    await tester.ensureVisible(find.byKey(const Key('admin-save-product')));
    await tester.tap(find.byKey(const Key('admin-save-product')));
    await tester.pumpAndSettle();
    expect(
      container
          .read(storeProvider)
          .products
          .firstWhere((item) => item.id == product.id)
          .name,
      renamedProduct,
    );
    await tester.enterText(search, renamedProduct);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(Key('admin-product-actions-${product.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive product'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('admin-confirm-archive-product')));
    await tester.pumpAndSettle();

    expect(
      container
          .read(storeProvider)
          .products
          .firstWhere((item) => item.id == product.id)
          .active,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('admin-catalogue-archived')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('admin-product-actions-${product.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore product'));
    await tester.pumpAndSettle();

    expect(
      container
          .read(storeProvider)
          .products
          .firstWhere((item) => item.id == product.id)
          .active,
      isTrue,
    );
  });

  testWidgets('admin can make delivery free or set a custom charge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: KoyasAdminApp()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-email')),
      'staff@koyas.in',
    );
    await tester.tap(find.byKey(const Key('admin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-nav-pricing')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final editPricing = find.byKey(const Key('admin-edit-order-pricing'));
    await tester.scrollUntilVisible(
      editPricing,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(editPricing);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-free-delivery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-save-order-pricing')));
    await tester.pumpAndSettle();

    expect(container.read(storeProvider).baseDeliveryChargePaise, 0);
    expect(container.read(storeProvider).minimumOrderPaise, 0);

    await tester.tap(editPricing);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-free-delivery')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('admin-minimum-order')), '250');
    await tester.enterText(
      find.byKey(const Key('admin-delivery-charge')),
      '75',
    );
    await tester.enterText(
      find.byKey(const Key('admin-free-delivery-threshold')),
      '500',
    );
    await tester.tap(find.byKey(const Key('admin-save-order-pricing')));
    await tester.pumpAndSettle();

    final updated = container.read(storeProvider);
    expect(updated.baseDeliveryChargePaise, 7500);
    expect(updated.freeDeliveryThresholdPaise, 50000);
    expect(updated.minimumOrderPaise, 25000);
  });

  testWidgets('admin creates and removes a custom product offer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: KoyasAdminApp()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-email')),
      'staff@koyas.in',
    );
    await tester.tap(find.byKey(const Key('admin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-nav-pricing')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final product = container
        .read(storeProvider)
        .products
        .firstWhere((product) => product.pricePaise > 100);
    final offerPaise = product.pricePaise ~/ 2;
    expect(
      container
          .read(storeProvider)
          .products
          .every((product) => product.discountPricePaise == null),
      isTrue,
    );

    final addOffer = find.byKey(const Key('admin-add-offer'));
    await tester.scrollUntilVisible(
      addOffer,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(addOffer);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-offer-product-search')),
      product.name,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('admin-offer-product-${product.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-offer-price')),
      (offerPaise / 100).toStringAsFixed(2),
    );
    await tester.tap(find.byKey(const Key('admin-save-offer')));
    await tester.pumpAndSettle();

    expect(
      container.read(storeProvider).productById(product.id)?.discountPricePaise,
      offerPaise,
    );
    final offerRow = find.byKey(Key('admin-active-offer-${product.id}'));
    await tester.ensureVisible(offerRow);
    final changeOffer = find.descendant(
      of: offerRow,
      matching: find.text('Change'),
    );
    await tester.tap(changeOffer);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-remove-offer')));
    await tester.pumpAndSettle();

    expect(
      container.read(storeProvider).productById(product.id)?.discountPricePaise,
      isNull,
    );
  });

  testWidgets('admin creates and disables a minimum-buy free-product offer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: KoyasAdminApp()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-email')),
      'staff@koyas.in',
    );
    await tester.tap(find.byKey(const Key('admin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-nav-pricing')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final freeProduct = container
        .read(storeProvider)
        .products
        .firstWhere((product) => product.isAvailable);
    final addOffer = find.byKey(const Key('admin-add-cart-offer'));
    await tester.scrollUntilVisible(
      addOffer,
      600,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(addOffer);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-cart-offer-code')),
      'FREE250',
    );
    await tester.enterText(
      find.byKey(const Key('admin-cart-offer-title')),
      'Free product on ₹250',
    );
    await tester.enterText(
      find.byKey(const Key('admin-cart-offer-minimum')),
      '250',
    );
    await tester.tap(
      find.byKey(const Key('admin-cart-offer-choose-free-product')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-offer-product-search')),
      freeProduct.name,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('admin-offer-product-${freeProduct.id}')));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('admin-save-cart-offer'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final created = container
        .read(storeProvider)
        .offers
        .firstWhere((offer) => offer.code == 'FREE250');
    expect(created.minimumSubtotalPaise, 25000);
    expect(created.freeProductId, freeProduct.id);
    expect(created.active, isTrue);

    final edit = find.byKey(Key('admin-edit-cart-offer-${created.id}'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final active = find.byKey(const Key('admin-cart-offer-active'));
    await tester.ensureVisible(active);
    await tester.tap(active);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(
      container
          .read(storeProvider)
          .offers
          .firstWhere((offer) => offer.id == created.id)
          .active,
      isFalse,
    );
  });

  testWidgets('admin switches daily, monthly, and yearly sales analytics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: KoyasAdminApp()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-email')),
      'staff@koyas.in',
    );
    await tester.tap(find.byKey(const Key('admin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-nav-analytics')));
    await tester.pumpAndSettle();

    final analytics = find.byKey(const Key('admin-sales-analytics'));
    await tester.scrollUntilVisible(
      analytics,
      600,
      scrollable: find.byType(Scrollable).first,
    );
    expect(analytics, findsOneWidget);
    expect(find.text('Most ordered products'), findsOneWidget);
    expect(find.text('Sales value'), findsOneWidget);
    expect(find.text('Items sold'), findsOneWidget);
    expect(find.text('Average order'), findsOneWidget);

    final daily = find.byKey(const Key('admin-analytics-daily'));
    final monthly = find.byKey(const Key('admin-analytics-monthly'));
    final yearly = find.byKey(const Key('admin-analytics-yearly'));
    expect(tester.widget<ChoiceChip>(daily).selected, isTrue);

    await tester.tap(monthly);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(monthly).selected, isTrue);

    await tester.tap(yearly);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(yearly).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin operates delivery details, closures, and cash payments', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final printedOrders = <CustomerOrder>[];
    var blockPrinting = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderBillPrinterProvider.overrideWithValue((order) {
            if (blockPrinting) throw StateError('Allow pop-ups to print.');
            printedOrders.add(order);
          }),
        ],
        child: const KoyasAdminApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-email')),
      'staff@koyas.in',
    );
    await tester.tap(find.byKey(const Key('admin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-nav-orders')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);

    final details = find.byKey(const Key('admin-order-details-KOY34621'));
    await tester.ensureVisible(details);
    expect(find.text('Ayesha Rahman'), findsOneWidget);
    expect(
      find.textContaining('18, Masab Tank Road, Hyderabad – 500028'),
      findsOneWidget,
    );
    await tester.tap(details);
    await tester.pumpAndSettle();

    final detailsDialog = find.byKey(
      const Key('admin-order-details-dialog-KOY34621'),
    );
    expect(
      find.descendant(of: detailsDialog, matching: find.text('Ayesha Rahman')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: detailsDialog,
        matching: find.text('+91 98490 11223'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('18, Masab Tank Road, Hyderabad – 500028'),
      findsOneWidget,
    );
    expect(find.text('Call on arrival; use the side gate.'), findsOneWidget);

    final printBill = find.byKey(const Key('admin-print-bill-KOY34621'));
    await tester.tap(printBill);
    await tester.pumpAndSettle();
    expect(find.text('Allow pop-ups to print.'), findsOneWidget);
    expect(printedOrders, isEmpty);
    blockPrinting = false;
    final originalOrder = container
        .read(storeProvider)
        .orders
        .firstWhere((order) => order.id == 'KOY34621');
    await tester.tap(printBill);
    await tester.pumpAndSettle();
    expect(find.text('Allow pop-ups to print.'), findsNothing);
    expect(printedOrders.single, same(originalOrder));
    expect(originalOrder.paymentStatus, PaymentStatus.pending);
    expect(originalOrder.status, OrderStatus.placed);

    await tester.tap(
      find.byKey(const Key('admin-close-order-details-KOY34621')),
    );
    await tester.pumpAndSettle();

    final markPaid = find.byKey(const Key('admin-mark-paid-KOY34619'));
    await tester.ensureVisible(markPaid);
    expect(find.byKey(const Key('admin-advance-KOY34619')), findsNothing);
    await tester.tap(markPaid);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-confirm-payment-KOY34619')));
    await tester.pumpAndSettle();

    final paidOrder = container
        .read(storeProvider)
        .orders
        .firstWhere((order) => order.id == 'KOY34619');
    expect(paidOrder.paymentStatus, PaymentStatus.paid);
    expect(paidOrder.paidAt, isNotNull);
    expect(find.byKey(const Key('admin-advance-KOY34619')), findsOneWidget);

    final paidDetails = find.byKey(const Key('admin-order-details-KOY34619'));
    await tester.ensureVisible(paidDetails);
    await tester.tap(paidDetails);
    await tester.pumpAndSettle();
    // A live update while the dialog is open must also reach the printer.
    container.read(storeProvider.notifier).advanceOrder('KOY34619');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-print-bill-KOY34619')));
    await tester.pumpAndSettle();
    expect(printedOrders.last.paymentStatus, PaymentStatus.paid);
    expect(printedOrders.last.status, OrderStatus.collected);
    await tester.tap(
      find.byKey(const Key('admin-close-order-details-KOY34619')),
    );
    await tester.pumpAndSettle();

    final cancel = find.byKey(const Key('admin-cancel-KOY34620'));
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-confirm-cancel-KOY34620')));
    await tester.pumpAndSettle();
    expect(
      container
          .read(storeProvider)
          .orders
          .firstWhere((order) => order.id == 'KOY34620')
          .status,
      OrderStatus.cancelled,
    );

    final reject = find.byKey(const Key('admin-reject-KOY34621'));
    await tester.ensureVisible(reject);
    await tester.tap(reject);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-confirm-reject-KOY34621')));
    await tester.pumpAndSettle();
    expect(
      container
          .read(storeProvider)
          .orders
          .firstWhere((order) => order.id == 'KOY34621')
          .status,
      OrderStatus.rejected,
    );
    expect(tester.takeException(), isNull);
  });
}
