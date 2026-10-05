// Optional visual QA artifact: flutter test --no-pub tool/catalogue_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/admin/admin_app.dart';
import 'package:koyas_supermarket/core/theme/app_theme.dart';
import 'package:koyas_supermarket/core/utils/product_grid_layout.dart';
import 'package:koyas_supermarket/features/products/screens/categories_screen.dart';
import 'package:koyas_supermarket/features/products/widgets/product_card.dart';
import 'package:koyas_supermarket/features/store/data/generated_product_catalog.dart';
import 'package:koyas_supermarket/features/store/data/customer_catalog_categories.dart';

void main() {
  testWidgets('render corrected product photos on compact phone cards', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final font = FontLoader('Manrope')
        ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await Future.wait([font.load(), icons.load()]);
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const names = [
      'AMUL BUTTER MILK RS15',
      'AMULYA 500G RS 255',
      'DBR HONEY RS 125',
      'SABJI MASALA RS 39',
      'CHOLE MSLA EV RS 92',
      'TANDOORI CHICKEN RS 49',
    ];
    final products = names
        .map(
          (name) => GeneratedProductCatalog.products.firstWhere(
            (product) => product.billingName == name,
          ),
        )
        .toList();
    const key = Key('product-photo-preview');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              appBar: AppBar(title: const Text('Updated catalogue')),
              body: LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: ProductGridLayout.delegate(
                    context,
                    constraints.maxWidth - 32,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) =>
                      ProductCard(product: products[index]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byKey(key));
      await Future.wait(
        tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => precacheImage(image.image, context)),
      );
    });
    await tester.pumpAndSettle();
    expect(find.text('ADD'), findsNothing);
    expect(tester.takeException(), isNull);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    _repaintPreview(boundary);
    await tester.pump();
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'outputs/catalogue_review/corrected-products-phone.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  });

  testWidgets('render client category preview', (tester) async {
    await tester.runAsync(() async {
      final font = FontLoader('Manrope')
        ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await Future.wait([font.load(), icons.load()]);
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const key = Key('preview');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const CategoriesScreen(),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(Scaffold).last);
      await Future.wait(
        tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => precacheImage(image.image, context)),
      );
    });
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    _repaintPreview(boundary);
    await tester.pump();
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('outputs/catalogue_review/categories-phone.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1400.0]) {
    testWidgets('render admin category pictures at width $width', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final font = FontLoader('Manrope')
          ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await Future.wait([font.load(), icons.load()]);
      });
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const key = Key('admin-category-preview');
      await tester.pumpWidget(
        const RepaintBoundary(
          key: key,
          child: ProviderScope(child: KoyasAdminApp()),
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
      await tester.tap(find.byKey(const Key('admin-nav-inventory')));
      await tester.pumpAndSettle();
      final category = CustomerCatalogCategories.all.first;
      final chip = find.byKey(Key('admin-category-${category.id}'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      final picker = find.byKey(const Key('admin-category-picker'));
      await tester.ensureVisible(picker);
      await tester.pumpAndSettle();
      await _captureAdmin(tester, key, 'inventory-${width.toInt()}');

      final add = find.byKey(const Key('admin-add-product'));
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      final dropdown = find.byKey(const Key('admin-product-category'));
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await _captureAdmin(tester, key, 'category-menu-${width.toInt()}');
    });
  }
}

Future<void> _captureAdmin(WidgetTester tester, Key key, String name) async {
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold).last);
    await Future.wait(
      tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => precacheImage(image.image, context)),
    );
  });
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  _repaintPreview(boundary);
  await tester.pump();
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('outputs/category_review/admin-$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

// Paint a complete fresh frame, including static labels and borders, before
// reading the preview pixels.
void _repaintPreview(RenderObject object) {
  object.markNeedsPaint();
  object.visitChildren(_repaintPreview);
}
