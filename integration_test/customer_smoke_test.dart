import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:koyas_supermarket/core/theme/app_colors.dart';
import 'package:koyas_supermarket/core/widgets/koyas_button.dart';
import 'package:koyas_supermarket/features/products/widgets/product_card.dart';
import 'package:koyas_supermarket/main.dart' as app;

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('customer shopping and pickup smoke flow', (tester) async {
    await app.main();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await _pumpUi(tester);

    expect(find.text('Groceries made simple.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('customer-login')));
    await _pumpUi(tester);
    expect(find.byKey(const Key('home-store-title')), findsOneWidget);

    await tester.tap(find.text('Categories'));
    await _pumpUi(tester);
    expect(find.text('Categories'), findsWidgets);

    await tester.tap(find.text('Atta').first);
    await _pumpUi(tester);
    expect(find.byKey(const Key('product-search')), findsOneWidget);

    final selectedCategory = find.widgetWithText(ChoiceChip, 'Atta');
    final allCategory = find.widgetWithText(ChoiceChip, 'All');
    expect(selectedCategory, findsOneWidget);
    expect(allCategory, findsOneWidget);
    expect(tester.widget<ChoiceChip>(selectedCategory).selected, isTrue);

    final selectedLabel = find.descendant(
      of: selectedCategory,
      matching: find.text('Atta'),
    );
    final allLabel = find.descendant(
      of: allCategory,
      matching: find.text('All'),
    );
    expect(
      DefaultTextStyle.of(tester.element(selectedLabel)).style.color,
      AppColors.brand700,
    );
    expect(
      DefaultTextStyle.of(tester.element(allLabel)).style.color,
      AppColors.ink,
    );

    final firstProduct = find.byType(ProductCard).first;
    await tester.ensureVisible(firstProduct);
    final card = tester.widget<ProductCard>(firstProduct);
    if ((card.family?.variants.length ?? 1) > 1) {
      await tester.tap(find.byKey(Key('choose-size-${card.product.id}')));
      await _pumpUi(tester);
      expect(find.text('Choose a pack size'), findsOneWidget);
      final variant = card.family!.variants.firstWhere((p) => p.isAvailable);
      await tester.tap(find.byKey(Key('variant-add-${variant.id}')));
      await _pumpUi(tester);
      await tester.tap(find.byKey(const Key('close-variant-sheet')));
    } else {
      await tester.tap(find.byKey(Key('add-product-${card.product.id}')));
    }
    await _pumpUi(tester);
    await tester.tap(find.byKey(const Key('view-active-cart')));
    await _pumpUi(tester);

    expect(find.text('Your cart'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
    final fulfilmentButton = find.widgetWithText(
      KoyasButton,
      'Choose fulfilment',
    );
    expect(fulfilmentButton, findsOneWidget);
    await tester.ensureVisible(fulfilmentButton);
    await tester.tap(fulfilmentButton);
    await _pumpUi(tester);
    expect(find.text('Store pickup'), findsOneWidget);
    await tester.tap(find.text('Store pickup'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await _pumpUi(tester);

    expect(find.text('Review and pay'), findsOneWidget);
    expect(find.text('Payment method'), findsOneWidget);
    expect(find.text('Cash or UPI at pickup'), findsOneWidget);
    expect(find.text('Pickup day'), findsNothing);
    expect(find.text('When would you like to collect?'), findsNothing);
    expect(find.text('Schedule'), findsNothing);
    expect(find.textContaining('Pickup window'), findsNothing);
    expect(find.textContaining('9:00 AM'), findsNothing);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
