import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/products/product_variants.dart';
import 'package:koyas_supermarket/features/products/screens/product_detail_screen.dart';
import 'package:koyas_supermarket/features/store/data/generated_product_catalog.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

void main() {
  final products = GeneratedProductCatalog.products;

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
    expect(find.text('Choose quantity'), findsOneWidget);
    expect(find.byKey(Key('product-size-${oneKg.id}')), findsOneWidget);

    await tester.tap(find.byKey(Key('product-size-${oneKg.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('detail-add-to-cart')));
    await tester.pump();

    final cart = container.read(storeProvider).cartQuantities;
    expect(cart[oneKg.id], 1);
    expect(cart[fiveKg.id], isNull);
  });
}
