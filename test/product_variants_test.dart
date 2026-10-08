import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/products/product_variants.dart';
import 'package:koyas_supermarket/features/products/models/product.dart';
import 'package:koyas_supermarket/features/products/screens/product_detail_screen.dart';
import 'package:koyas_supermarket/features/products/widgets/product_card.dart';
import 'package:koyas_supermarket/features/products/widgets/product_variant_sheet.dart';
import 'package:koyas_supermarket/features/store/data/generated_product_catalog.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

void main() {
  final products = GeneratedProductCatalog.products;

  testWidgets(
    'X and system back discard draft additions and preserve confirmed cart items',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(storeProvider.notifier)..loginDemo();
      final milk = [
        _product(id: 'milk-500', name: 'Koya Milk', unit: '500 ml'),
        _product(id: 'milk-1l', name: 'Koya Milk', unit: '1 L'),
      ];
      controller.loginDemo(isAdmin: true);
      for (final p in milk) {
        controller.adminSaveProduct(p);
      }
      controller.addToCart(milk.first.id);
      final family = ProductVariants.familyFor(
        product: milk.first,
        catalogue: milk,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      showProductVariantSheet(context: context, family: family),
                  child: const Text('Choose'),
                ),
              ),
            ),
          ),
        ),
      );
      for (final closeWithX in [true, false]) {
        await tester.tap(find.text('Choose'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('variant-add-${milk.last.id}')));
        await tester.pump();
        expect(container.read(storeProvider).cartQuantities, {
          milk.first.id: 1,
        });
        if (closeWithX) {
          await tester.tap(find.byKey(const Key('close-variant-sheet')));
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(container.read(storeProvider).cartQuantities, {
          milk.first.id: 1,
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'variant confirmation merges other cart edits atomically and rejects changed stock',
    () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final controller = c.read(storeProvider.notifier)
        ..loginDemo(isAdmin: true);
      final first = _product(id: 'test-first', name: 'First'),
          second = _product(id: 'test-second', name: 'Second');
      controller.adminSaveProduct(first);
      controller.adminSaveProduct(second);
      controller.addToCart(
        first.id,
      ); // A cart restore/edit after the sheet opened.
      controller.confirmCartSelection(
        expectedUserId: 'demo-customer',
        baseline: {first.id: 0},
        selection: {first.id: 2},
      );
      expect(c.read(storeProvider).cartQuantities[first.id], 3);
      controller.adminSaveProduct(second.copyWith(stockQuantity: 0));
      final before = Map.of(c.read(storeProvider).cartQuantities);
      expect(
        () => controller.confirmCartSelection(
          expectedUserId: 'demo-customer',
          baseline: {first.id: 3, second.id: 0},
          selection: {first.id: 0, second.id: 1},
        ),
        throwsA(isA<StoreValidationException>()),
      );
      expect(c.read(storeProvider).cartQuantities, before);
      expect(
        () => controller.confirmCartSelection(
          expectedUserId: 'foreign',
          baseline: {first.id: 3},
          selection: {first.id: 0},
        ),
        throwsA(isA<StoreValidationException>()),
      );
      expect(c.read(storeProvider).cartQuantities, before);
    },
  );

  test('different quantities collapse into one exact product family', () {
    final attaProducts = products
        .where((product) => product.name.startsWith('Aashirvaad Atta Multi'))
        .toList(growable: false);
    final families = ProductVariants.collapse(
      visibleProducts: attaProducts,
      catalogue: products,
    );

    expect(families, hasLength(1));
    expect(families.single.name, 'Aashirvaad Atta Multi');
    expect(families.single.sizeLabels, <String>['1 kg', '5 kg']);
  });

  test('different formulas remain separate product families', () {
    final teaProducts = products.where(
      (product) => product.name.startsWith('Brooke Bond Red Label'),
    );
    final familyNames = ProductVariants.collapse(
      visibleProducts: teaProducts,
      catalogue: products,
    ).map((family) => family.name).toSet();

    expect(familyNames, contains('Brooke Bond Red Label'));
    expect(familyNames, contains('Brooke Bond Red Label Natural Care'));
  });

  test('pack sizes can come from the product unit field', () {
    final variants = <Product>[
      _product(id: 'milk-500', name: 'Koya Fresh Milk', unit: '500 ml'),
      _product(id: 'milk-1l', name: 'Koya Fresh Milk', unit: '1 L'),
    ];

    final families = ProductVariants.collapse(
      visibleProducts: variants,
      catalogue: variants,
    );

    expect(families, hasLength(1));
    expect(families.single.sizeLabels, <String>['500 ml', '1 L']);
  });

  test('multipack measurements remain clear size options', () {
    final variants = <Product>[
      _product(id: 'snack-2', name: 'Koya Snack 2 x 100 g'),
      _product(id: 'snack-4', name: 'Koya Snack 4 x 100 g'),
    ];

    final families = ProductVariants.collapse(
      visibleProducts: variants,
      catalogue: variants,
    );

    expect(families, hasLength(1));
    expect(families.single.name, 'Koya Snack');
    expect(families.single.sizeLabels, <String>['2 × 100 g', '4 × 100 g']);
  });

  testWidgets('selected quantity controls the exact SKU added to cart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fiveKg = products.firstWhere(
      (product) => product.name == 'Aashirvaad Atta Multi 5 kg',
    );
    final oneKg = products.firstWhere(
      (product) => product.name == 'Aashirvaad Atta Multi 1 kg',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(storeProvider.notifier);
    controller.loginDemo(isAdmin: true);
    controller.adminSaveProduct(oneKg.copyWith(stockQuantity: 5));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ProductDetailScreen(productId: fiveKg.id)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aashirvaad Atta Multi'), findsOneWidget);
    expect(find.text('Choose a pack size'), findsOneWidget);
    expect(find.byKey(Key('product-size-${oneKg.id}')), findsOneWidget);

    await tester.tap(find.byKey(Key('product-size-${oneKg.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('detail-add-to-cart')));
    await tester.pumpAndSettle();

    final cart = container.read(storeProvider).cartQuantities;
    expect(cart[oneKg.id], 1);
    expect(cart[fiveKg.id], isNull);
    expect(find.byKey(const ValueKey('active-cart-ribbon')), findsOneWidget);
  });

  testWidgets('product card opens pack options and adds the exact size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fiveKg = products.firstWhere(
      (product) => product.name == 'Aashirvaad Atta Multi 5 kg',
    );
    final oneKg = products.firstWhere(
      (product) => product.name == 'Aashirvaad Atta Multi 1 kg',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(storeProvider.notifier);
    controller.loginDemo(isAdmin: true);
    controller.adminSaveProduct(oneKg.copyWith(stockQuantity: 5));
    final currentProducts = container.read(storeProvider).products;
    final family = ProductVariants.familyFor(
      product: currentProducts.firstWhere((product) => product.id == fiveKg.id),
      catalogue: currentProducts,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 230,
              height: 400,
              child: ProductCard(
                product: family.representative,
                family: family,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(Key('choose-size-${family.representative.id}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose a pack size'), findsOneWidget);
    expect(find.byKey(Key('variant-option-${oneKg.id}')), findsOneWidget);
    expect(find.byKey(Key('variant-option-${fiveKg.id}')), findsOneWidget);

    await tester.tap(find.byKey(Key('variant-add-${oneKg.id}')));
    await tester.pump();

    expect(container.read(storeProvider).cartQuantities, isEmpty);
    await tester.tap(find.byKey(const Key('confirm-variant-selection')));
    await tester.pumpAndSettle();
    final cart = container.read(storeProvider).cartQuantities;
    expect(cart[oneKg.id], 1);
    expect(cart[fiveKg.id], isNull);
    expect(find.byKey(const Key('confirm-variant-selection')), findsNothing);
  });
}

Product _product({
  required String id,
  required String name,
  String unit = '1 pack',
}) {
  return Product(
    id: id,
    categoryId: 'test-category',
    name: name,
    description: 'Test product',
    unit: unit,
    pricePaise: 1000,
    stockQuantity: 10,
    visualKey: 'grocery',
    brand: 'Koya',
  );
}
