import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/products/product_search.dart';
import 'package:koyas_supermarket/features/products/providers/product_search_history_provider.dart';
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
    expect(results.first.subcategory.toLowerCase(), isNot(contains('dish')));
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

  test('common spoken grocery terms are easy to search', () {
    final milk = ProductSearch.search(products: products, query: 'doodh');
    final rice = ProductSearch.search(products: products, query: 'chawal');
    final soap = ProductSearch.search(products: products, query: 'sabun');

    expect(milk, isNotEmpty);
    expect(
      milk.first.name.toLowerCase() + milk.first.subcategory.toLowerCase(),
      contains('milk'),
    );
    expect(rice, isNotEmpty);
    expect(
      rice.first.name.toLowerCase() + rice.first.subcategory.toLowerCase(),
      contains('rice'),
    );
    expect(soap, isNotEmpty);
    expect(
      soap.first.name.toLowerCase() + soap.first.subcategory.toLowerCase(),
      contains('soap'),
    );
  });

  test('catalogue filters exclude archived products before ranking', () {
    final archived = products.first.copyWith(active: false);
    final results = ProductSearch.search(
      products: [archived, products[1]],
      query: '',
      filter: (product) => product.active,
    );

    expect(results, hasLength(1));
    expect(results.single.id, products[1].id);
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

  test('type-ahead suggestions include useful brands and products', () {
    final suggestions = ProductSearch.suggestions(
      products: products,
      query: 'surf',
    );

    expect(suggestions, isNotEmpty);
    expect(
      suggestions.any(
        (suggestion) =>
            suggestion.kind == ProductSearchSuggestionKind.brand &&
            suggestion.label.toLowerCase().contains('surf'),
      ),
      isTrue,
    );
    expect(
      suggestions.any(
        (suggestion) => suggestion.kind == ProductSearchSuggestionKind.product,
      ),
      isTrue,
    );
    expect(
      suggestions.map((suggestion) => suggestion.query).toSet().length,
      suggestions.length,
    );
  });

  test('broad intent suggestions stay presentable and diverse', () {
    final suggestions = ProductSearch.suggestions(
      products: products,
      query: 'washing',
    );
    final productSuggestions = suggestions
        .where((suggestion) => suggestion.product != null)
        .toList(growable: false);
    final brandCounts = <String, int>{};
    for (final suggestion in productSuggestions) {
      final brand = suggestion.product!.brand.toLowerCase();
      brandCounts[brand] = (brandCounts[brand] ?? 0) + 1;
    }

    expect(productSuggestions, isNotEmpty);
    expect(
      productSuggestions.map((suggestion) => suggestion.label),
      isNot(contains('Acid')),
    );
    expect(brandCounts.values.every((count) => count <= 2), isTrue);
  });

  test('recent search history is deduplicated and bounded', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final history = container.read(productSearchHistoryProvider.notifier);

    for (final query in [
      'Atta',
      'Rice',
      'Milk',
      'Biscuits',
      'Detergent',
      'Shampoo',
      'atta',
    ]) {
      history.add(query);
    }

    expect(container.read(productSearchHistoryProvider), hasLength(6));
    expect(container.read(productSearchHistoryProvider).first, 'atta');
    expect(
      container
          .read(productSearchHistoryProvider)
          .where((query) => query.toLowerCase() == 'atta'),
      hasLength(1),
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

  testWidgets('search discovery, commit and recent searches work together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProductListingScreen())),
    );
    await tester.pump();

    expect(find.byKey(const Key('search-discovery')), findsOneWidget);
    expect(find.text('Popular searches'), findsOneWidget);
    expect(find.text('Shop by category'), findsOneWidget);

    await tester.tap(find.text('Detergent'));
    await tester.pump();

    expect(find.byKey(const Key('product-result-count')), findsOneWidget);
    expect(find.textContaining('results for "Detergent"'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clear-product-search')));
    await tester.pump();

    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('Detergent'), findsAtLeastNWidgets(2));
  });

  testWidgets('submitting a typed query opens the result grid', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProductListingScreen())),
    );
    await tester.enterText(find.byKey(const Key('product-search')), 'washing');
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('search-suggestions')), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(find.byKey(const Key('product-result-count')), findsOneWidget);
    expect(find.textContaining('results for "washing"'), findsOneWidget);
  });
}
