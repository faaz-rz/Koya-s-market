import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/core/theme/app_theme.dart';
import 'package:koyas_supermarket/features/products/screens/categories_screen.dart';
import 'package:koyas_supermarket/features/products/widgets/category_tile.dart';
import 'package:koyas_supermarket/features/store/data/customer_catalog_categories.dart';
import 'package:koyas_supermarket/features/store/data/generated_product_catalog.dart';

void main() {
  test('client departments contain the right products', () {
    final categories = {
      for (final c in CustomerCatalogCategories.all) c.id: c.name,
    };
    const examples = {
      'TDAL': 'Dal',
      'BESAN': 'Atta',
      'WHEAT': 'Grains',
      'I RAVA 500G': 'Grains',
      'KORALU': 'Millets',
      'CHAT MSLA EV RS 94': 'Masala Box',
      'GARAM MASALA EV RS 106': 'Garam Masalas',
      'DALCHINI CIGAR 100G': 'Spices',
      'TIKHA LAL 100G RS 60': 'Spices',
      'GD 1L': 'Cooking Oils',
      'A POOJA OIL 5LTR RS 1100': 'Pooja Oils & Items',
      'CUPS ASHIRWAD': 'Pooja Oils & Items',
      'PAPAD LIJATH': 'Papads',
      'KINDER JOY RS 50': 'Chocolates',
      'AMUL ICE CREAM RS 35': 'Ice Creams',
      'COW GEE ASRVD RS10': 'Ghee',
      'UNIBIC RS 10': 'Biscuits',
      'VIM LQ RS 99': 'Home Care',
      'SRF XL RS 40': 'Detergents',
      'COMFT RS 125': 'Fabric Care',
      'HIMA BBY HO RS 85': 'Kids Care',
      'KAJAL EYETX': 'Body Care',
      'MILK MASQ 1 LTR RS 80': 'Milk & Dairy',
      'AMUL BUTTER MILK RS15': 'Milk & Dairy',
      'INDIA GATE 5KG PKT': 'Basmati',
      'INDIAGATE SONA 26KG': 'Grains',
      'GREEN COLOR': 'Food Colour & Essences',
    };
    for (final entry in examples.entries) {
      final product = GeneratedProductCatalog.products.firstWhere(
        (p) => p.billingName == entry.key,
      );
      expect(categories[product.categoryId], entry.value, reason: entry.key);
    }
    for (final category in CustomerCatalogCategories.all) {
      expect(
        CustomerCatalogCategories.visualForName(category.name),
        category.visualKey,
      );
    }
  });

  for (final width in [320.0, 360.0, 375.0, 390.0, 414.0, 430.0, 768.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets(
        'all category labels fit at width $width and text scale $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: AppTheme.light,
                home: const CategoriesScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final scrollable = find.byType(Scrollable).first;
          for (final category in CustomerCatalogCategories.all) {
            await tester.scrollUntilVisible(
              find.text(category.name),
              300,
              scrollable: scrollable,
              maxScrolls: 100,
            );
            await tester.pump();
            expect(tester.takeException(), isNull, reason: category.name);
          }
          expect(find.byType(CategoryTile), findsWidgets);
        },
      );
    }
  }
}
