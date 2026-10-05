import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/core/theme/app_theme.dart';
import 'package:koyas_supermarket/core/widgets/customer_tab_transition.dart';
import 'package:koyas_supermarket/core/widgets/koyas_button.dart';
import 'package:koyas_supermarket/features/products/screens/categories_screen.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

void main() {
  testWidgets(
    'compact loading buttons preserve size and prevent repeated activation',
    (tester) async {
      var loading = false, clicks = 0;
      final semantics = tester.ensureSemantics();
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return KoyasButton(
                    label: 'Send verification code',
                    icon: Icons.mail_outline,
                    expand: false,
                    loading: loading,
                    onPressed: () {
                      clicks++;
                      rebuild(() => loading = true);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
      final button = find.byType(FilledButton),
          size = tester.getSize(find.byType(FilledButton));
      try {
        expect(
          tester.getSemantics(find.byType(KoyasButton)),
          matchesSemantics(
            label: 'Send verification code',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
      } finally {
        semantics.dispose();
      }
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getSize(button), size);
      await tester.tap(button);
      expect(clicks, 1);
      rebuild(() => loading = false);
      await tester.pumpAndSettle();
      expect(tester.getSize(button), size);
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'tab fade preserves child state and respects reduced motion=$reduced',
      (tester) async {
        var index = 0;
        late StateSetter update;
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return CustomerTabTransition(
                      index: index,
                      child: ListView.builder(
                        controller: scroll,
                        itemCount: 100,
                        itemBuilder: (_, i) =>
                            SizedBox(height: 50, child: Text('Item $i')),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        scroll.jumpTo(400);
        await tester.pump();
        final before = tester.state(find.byType(Scrollable));
        for (final next in [1, 2, 3, 0, 2]) {
          update(() => index = next);
          await tester.pump(const Duration(milliseconds: 16));
        }
        final fade = tester.widget<FadeTransition>(
          find
              .descendant(
                of: find.byType(CustomerTabTransition),
                matching: find.byType(FadeTransition),
              )
              .first,
        );
        expect(fade.opacity.value, reduced ? 1 : lessThan(1));
        expect(tester.state(find.byType(Scrollable)), same(before));
        expect(scroll.offset, 400);
        await tester.pumpAndSettle();
        expect(fade.opacity.value, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'actual tab navigation preserves category scroll position after rapid changes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(child: KoyasApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-login')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-tab-categories')));
      await tester.pumpAndSettle();
      final grid = find
          .descendant(
            of: find.byType(CategoriesScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(grid, const Offset(0, -450));
      await tester.pumpAndSettle();
      final position = tester.state<ScrollableState>(grid).position,
          offset = tester.state<ScrollableState>(grid).position.pixels;
      expect(offset, greaterThan(0));
      for (final tab in ['orders', 'profile', 'home', 'categories']) {
        await tester.tap(find.byKey(Key('customer-tab-$tab')));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(grid).position, same(position));
      expect(position.pixels, offset);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'checkout ignores repeated submission and back, then confirms without empty-cart flash',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: KoyasApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-login')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      final store = container.read(storeProvider.notifier);
      final originalOrders = container.read(storeProvider).orders.length;
      store.addToCart(
        container
            .read(storeProvider)
            .products
            .firstWhere((p) => p.isAvailable)
            .id,
      );
      container.read(appRouterProvider).push('/checkout/payment');
      await tester.pumpAndSettle();
      final submit = find.byWidgetPredicate(
        (w) => w is KoyasButton && w.label.startsWith('Place order'),
      );
      await tester.ensureVisible(submit);
      final callback = tester.widget<KoyasButton>(submit).onPressed!;
      callback();
      callback();
      await tester.pump();
      expect(tester.widget<KoyasButton>(submit).loading, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Review and pay'), findsOneWidget);
      for (var i = 0; i < 70; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.text('There is nothing to pay for'), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(find.text('Order confirmed!'), findsOneWidget);
      expect(
        container.read(storeProvider).orders,
        hasLength(originalOrders + 1),
      );
      expect(container.read(storeProvider).cartItems, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
