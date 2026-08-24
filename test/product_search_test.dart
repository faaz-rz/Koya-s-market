import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/products/product_search.dart';
import 'package:koyas_supermarket/features/products/screens/product_listing_screen.dart';
import 'package:koyas_supermarket/features/store/data/generated_product_catalog.dart';

void main() {
  final products = GeneratedProductCatalog.products;

  test('intent search finds washing and laundry products', () {
    final results = ProductSearch.search(products: products, query: 'washing');
    final names = results.map((product) => product.name).toList();

    expect(results, isNotEmpty);
    expect(names.any((name) => name.startsWith('Surf Excel')), isTrue);
    expect(names.any((name) => name.startsWith('Ariel')), isTrue);
    expect(names.any((name) => name.startsWith('Tide')), isTrue);
    expect(names.any((name) => name.startsWith('Comfort')), isTrue);
    expect(
      results
          .take(20)
          .every(
            (product) =>
                !product.subcategory.toLowerCase().contains('body wash'),
          ),
      isTrue,
    );
  });

  test('multi-word intent keeps washing powder results focused', () {
    final results = ProductSearch.search(
      products: products,
      query: 'washing powder',
    );

    expect(results, isNotEmpty);
    expect(
      results.every(
        (product) =>
            product.name.toLowerCase().contains('powder') ||
            product.subcategory.toLowerCase().contains('powder'),
      ),
      isTrue,
    );
    expect(
      results.first.name.toLowerCase(),
      anyOf(contains('washing powder'), contains('detergent powder')),
    );
  });

  test('washing soap and dish washing understand grocery terminology', () {
    final laundryBars = ProductSearch.search(
      products: products,
      query: 'washing soap',
    );
    final dishwashing = ProductSearch.search(
      products: products,
      query: 'dish washing',
    );

    expect(laundryBars, isNotEmpty);
    expect(
      laundryBars.every(
        (product) =>
            product.name.toLowerCase().contains('detergent bar') ||
            product.name.toLowerCase().contains('washing soap') ||
            product.subcategory.toLowerCase().contains('laundry bar'),
      ),
      isTrue,
    );
    expect(dishwashing, isNotEmpty);
    expect(
      dishwashing.every(
        (product) =>
            product.name.toLowerCase().contains('dish') ||
            product.subcategory.toLowerCase().contains('dish'),
      ),
      isTrue,
    );
  });

  test('billing spellings, typos and canonical names remain searchable', () {
    final misspelledBiscuit = ProductSearch.search(
      products: products,
      query: 'biscot',
    );
    final oldBillingName = ProductSearch.search(
      products: products,
      query: 'srf exl',
    );
    final fuzzyBrand = ProductSearch.search(
      products: products,
      query: 'nilofer platinum',
    );

    expect(misspelledBiscuit.first.name.toLowerCase(), contains('biscuit'));
    expect(oldBillingName.first.name, startsWith('Surf Excel'));
    expect(
      fuzzyBrand.first.name,
      startsWith('Cafe Niloufer Platinum Tea Powder'),
    );
  });

  test('exact storefront names rank ahead of broad matches', () {
    final results = ProductSearch.search(products: products, query: 'M-Seal');
    expect(results.first.name, 'M-Seal');
  });

  test('category selection still limits smart search results', () {
    final categoryId = products
        .firstWhere((product) => product.name.startsWith('Surf Excel'))
        .categoryId;
    final results = ProductSearch.search(
      products: products,
      query: 'washing',
      categoryId: categoryId,
    );

    expect(results, isNotEmpty);
    expect(
      results.every((product) => product.categoryId == categoryId),
      isTrue,
    );
  });

  testWidgets('product screen uses smart search results', (tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final expectedFirst = ProductSearch.search(
      products: products,
      query: 'washing',
    ).first.name;

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProductListingScreen())),
    );
    await tester.enterText(find.byKey(const Key('product-search')), 'washing');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text(expectedFirst), findsOneWidget);
  });
}
