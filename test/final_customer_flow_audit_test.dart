import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/core/theme/app_theme.dart';
import 'package:koyas_supermarket/features/checkout/screens/address_setup_screen.dart';
import 'package:koyas_supermarket/features/notifications/services/push_preferences.dart';
import 'package:koyas_supermarket/features/products/models/product.dart';
import 'package:koyas_supermarket/features/products/product_variants.dart';
import 'package:koyas_supermarket/features/products/widgets/product_variant_sheet.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';
import 'push_session_test.dart' show TestPreferences;

class AuditStore extends StoreController {
  void newCustomer() {
    loginDemo();
    state = state.copyWith(
      addresses: [],
      selectedAddressId: '',
      profile: state.profile!.copyWith(name: '', phone: ''),
    );
  }
}

Future<ProviderContainer> address(WidgetTester tester, double scale) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final c = ProviderContainer(
    overrides: [
      storeProvider.overrideWith(AuditStore.new),
      firstLoginNotificationPromptProvider.overrideWithValue(false),
      pushPreferencesProvider.overrideWithValue(TestPreferences()),
    ],
  );
  addTearDown(c.dispose);
  (c.read(storeProvider.notifier) as AuditStore).newCustomer();
  c.read(appRouterProvider).go('/address/setup');
  await tester.pumpWidget(
    UncontrolledProviderScope(container: c, child: const KoyasApp()),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('address setup has labeled touch targets and readable contrast', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await address(tester, 1);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
    'address validation focuses a missing phone below the fold and makes correction clear',
    (tester) async {
      final c = await address(tester, 1);
      for (final entry in {
        'address-line': '12 Market Road',
        'address-pincode': '500008',
        'address-name': 'Test Customer',
      }.entries) {
        final field = find.byKey(Key(entry.key));
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-address')));
      await tester.pumpAndSettle();
      final editable = find.descendant(
        of: find.byKey(const Key('address-phone')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, true);
      expect(
        find.text('Enter a valid phone number').hitTestable(),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('address-phone')),
        '9876543210',
      );
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid phone number'), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-address')));
      await tester.pumpAndSettle();
      expect(c.read(storeProvider).addresses.single.phone, '9876543210');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final scale in [2.0, 3.0]) {
    testWidgets(
      'address entry with keyboard and $scale text stays usable on a small phone',
      (tester) async {
        final c = await address(tester, scale);
        for (final entry in {
          'address-line': '12 Market Road',
          'address-pincode': '500008',
          'address-name': 'Test Customer',
          'address-phone': '9876543210',
        }.entries) {
          final field = find.byKey(Key(entry.key));
          await tester.ensureVisible(field);
          await tester.enterText(field, entry.value);
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          await tester.pumpAndSettle();
          await tester.ensureVisible(field);
          expect(tester.takeException(), isNull);
        }
        FocusManager.instance.primaryFocus?.unfocus();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('save-address')));
        await tester.pumpAndSettle();
        expect(c.read(storeProvider).addresses, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'cart restore updates an open variant draft total without losing the shopper edits',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final controller = c.read(storeProvider.notifier)
        ..loginDemo(isAdmin: true);
      const product = Product(
        id: 'audit-pack',
        categoryId: 'test',
        name: 'Koya Milk',
        description: 'Milk',
        unit: '1 L',
        pricePaise: 1000,
        stockQuantity: 10,
        visualKey: 'grocery',
        brand: 'Koya',
      );
      controller.adminSaveProduct(product);
      final family = ProductVariants.familyFor(
        product: product,
        catalogue: [product],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.customer,
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
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('variant-add-audit-pack')));
      await tester.pump();
      controller.addToCart(product.id);
      controller.addToCart(product.id);
      await tester.pump();
      expect(find.text('Item total: ₹30'), findsOneWidget);
      await tester.tap(find.byKey(const Key('variant-remove-audit-pack')));
      await tester.pump();
      expect(find.text('Item total: ₹20'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-variant-selection')));
      await tester.pumpAndSettle();
      expect(c.read(storeProvider).cartQuantities[product.id], 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
