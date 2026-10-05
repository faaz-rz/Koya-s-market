import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/admin/admin_app.dart';
import 'package:koyas_supermarket/features/products/widgets/category_tile.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);
  for (final width in [320.0, 390.0, 430.0, 1400.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets(
        'admin category pictures, filtering and editor at $width / $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await tester.pumpWidget(const ProviderScope(child: KoyasAdminApp()));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('admin-email')),
            'staff@koyas.in',
          );
          await tester.ensureVisible(find.byKey(const Key('admin-login')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('admin-login')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Overview metrics');
          await tester.tap(find.byKey(const Key('admin-nav-analytics')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Analytics metrics');
          await tester.tap(find.byKey(const Key('admin-nav-inventory')));
          await tester.pumpAndSettle();

          final container = ProviderScope.containerOf(
            tester.element(find.byType(Scaffold).first),
          );
          final state = container.read(storeProvider);
          final picker = find.byKey(const Key('admin-category-picker'));
          await tester.scrollUntilVisible(
            picker,
            400,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            find.descendant(of: picker, matching: find.byType(CategoryPicture)),
            findsNWidgets(state.categories.length),
          );
          for (final category in state.categories) {
            final chip = find.byKey(Key('admin-category-${category.id}'));
            final image = tester.widget<Image>(
              find.descendant(of: chip, matching: find.byType(Image)),
            );
            expect(
              (image.image as AssetImage).assetName,
              CategoryTile.imageAssetFor(category.visualKey),
              reason: category.name,
            );
          }

          final category = state.categories.firstWhere(
            (category) => category.visualKey == 'food-colour',
          );
          final chip = find.byKey(Key('admin-category-${category.id}'));
          await tester.ensureVisible(chip);
          await tester.pumpAndSettle();
          await tester.tap(chip);
          await tester.pumpAndSettle();
          expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
          final otherProduct = state.products.firstWhere(
            (product) => product.categoryId != category.id,
          );
          expect(
            find.byKey(Key('admin-product-${otherProduct.id}')),
            findsNothing,
          );

          final add = find.byKey(const Key('admin-add-product'));
          await tester.ensureVisible(add);
          await tester.pumpAndSettle();
          await tester.tap(add);
          await tester.pumpAndSettle();
          final dropdown = find.byKey(const Key('admin-product-category'));
          await tester.ensureVisible(dropdown);
          await tester.pumpAndSettle();
          expect(
            find.widgetWithText(DropdownButtonFormField<String>, category.name),
            findsOneWidget,
          );
          final selectedPicture = tester.widget<CategoryPicture>(
            find.descendant(
              of: dropdown,
              matching: find.byType(CategoryPicture),
            ),
          );
          expect(selectedPicture.visualKey, category.visualKey);
          await tester.tap(dropdown);
          await tester.pumpAndSettle();
          final nextCategory = state.categories.firstWhere(
            (category) => category.visualKey == 'detergents',
          );
          final option = find.text(nextCategory.name);
          await tester.scrollUntilVisible(
            option,
            150,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.pumpAndSettle();
          await tester.tap(option);
          await tester.pumpAndSettle();
          final changedPicture = tester.widget<CategoryPicture>(
            find.descendant(
              of: dropdown,
              matching: find.byType(CategoryPicture),
            ),
          );
          expect(changedPicture.visualKey, nextCategory.visualKey);
          for (final field in {
            'admin-product-name': 'Category picture test product',
            'admin-product-description':
                'A test item in the selected department.',
            'admin-product-price': '49.00',
          }.entries) {
            final input = find.byKey(Key(field.key));
            await tester.ensureVisible(input);
            await tester.pumpAndSettle();
            await tester.enterText(input, field.value);
          }
          final save = find.byKey(const Key('admin-save-product'));
          await tester.ensureVisible(save);
          await tester.pumpAndSettle();
          await tester.tap(save);
          await tester.pumpAndSettle();
          final saved = container
              .read(storeProvider)
              .products
              .firstWhere(
                (product) => product.name == 'Category picture test product',
              );
          expect(saved.categoryId, nextCategory.id);
          expect(saved.visualKey, nextCategory.visualKey);
          expect(saved.pricePaise, 4900);
          // Department artwork must never become an invented SKU photo.
          expect(saved.imageAsset, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
