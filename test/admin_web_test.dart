import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/admin/admin_app.dart';
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
    expect(find.text('Orders today'), findsOneWidget);
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

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final state = container.read(storeProvider);
    final category = state.categories.first;
    final selectedProduct = state.products.firstWhere(
      (product) => product.categoryId == category.id,
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

    expect(
      find.byKey(Key('admin-product-${selectedProduct.id}')),
      findsOneWidget,
    );
    expect(find.byKey(Key('admin-product-${otherProduct.id}')), findsNothing);

    final increase = find.byKey(
      Key('admin-stock-increase-${selectedProduct.id}'),
    );
    await tester.ensureVisible(increase);
    await tester.tap(increase);
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

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final product = container.read(storeProvider).products.first;
    final inventory = find.byKey(const Key('admin-category-inventory'));
    await tester.scrollUntilVisible(
      inventory,
      700,
      scrollable: find.byType(Scrollable).first,
    );

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
    await tester.tap(outOfStockFilter);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(outOfStockFilter).selected, isTrue);
    expect(find.byKey(Key('admin-product-${product.id}')), findsNothing);
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
    expect(find.text('Product name'), findsOneWidget);
    expect(find.text('Stock quantity'), findsOneWidget);
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

    final context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context);
    final editPricing = find.byKey(const Key('admin-edit-delivery-pricing'));
    await tester.scrollUntilVisible(
      editPricing,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(editPricing);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-free-delivery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-save-delivery-pricing')));
    await tester.pumpAndSettle();

    expect(container.read(storeProvider).baseDeliveryChargePaise, 0);

    await tester.tap(editPricing);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-free-delivery')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-delivery-charge')),
      '75',
    );
    await tester.enterText(
      find.byKey(const Key('admin-free-delivery-threshold')),
      '500',
    );
    await tester.tap(find.byKey(const Key('admin-save-delivery-pricing')));
    await tester.pumpAndSettle();

    final updated = container.read(storeProvider);
    expect(updated.baseDeliveryChargePaise, 7500);
    expect(updated.freeDeliveryThresholdPaise, 50000);
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
}
