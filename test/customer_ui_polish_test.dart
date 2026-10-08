import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/core/theme/app_theme.dart';
import 'package:koyas_supermarket/core/theme/app_colors.dart';
import 'package:koyas_supermarket/core/widgets/customer_backdrop.dart';
import 'package:koyas_supermarket/features/home/screens/home_screen.dart';
import 'package:koyas_supermarket/features/products/product_variants.dart';
import 'package:koyas_supermarket/features/products/widgets/product_card.dart';
import 'package:koyas_supermarket/features/products/widgets/product_variant_sheet.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

void main() {
  test('customer title and button colours have accessible contrast', () {
    double contrast(Color first, Color second) {
      final a = first.computeLuminance(), b = second.computeLuminance();
      return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
    }

    expect(AppTheme.customer.appBarTheme.titleTextStyle?.color, AppColors.ink);
    for (final background in [
      AppColors.mint,
      AppColors.canvas,
      AppColors.peach,
      AppColors.surface,
    ]) {
      expect(contrast(AppColors.ink, background), greaterThanOrEqualTo(4.5));
      expect(
        contrast(AppColors.inkSecondary, background),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      contrast(AppColors.surface, AppColors.brand600),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets(
    'central cart keeps all four tab mappings, badges and back navigation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(storeProvider.notifier)..loginDemo();
      controller.addToCart(container.read(storeProvider).products.first.id);
      final router = container.read(appRouterProvider)..go('/categories');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const KoyasApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Open cart')), findsWidgets);
      for (final tab in ['orders', 'profile', 'home', 'categories']) {
        await tester.tap(find.byKey(Key('customer-tab-$tab')));
        await tester.pumpAndSettle();
        expect(
          router.routerDelegate.currentConfiguration.last.matchedLocation,
          '/$tab',
        );
        if (tab == 'home') {
          expect(find.byKey(const Key('home-store-title')), findsOneWidget);
          expect(find.text('Koya Stores'), findsOneWidget);
          expect(
            find.text(
              'Your neighbourhood supermarket,\nnow at your fingertips.',
            ),
            findsNothing,
          );
          expect(
            find.text(
              'Pickup from Koya Stores or get your order delivered today.',
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const Key('customer-open-cart')));
      await tester.pumpAndSettle();
      expect(find.text('Your cart'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/cart',
      );
      expect(
        find.ancestor(
          of: find.text('Your cart'),
          matching: find.byType(CustomerBackdrop),
        ),
        findsWidgets,
      );
      router.pop();
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/categories',
      );
      expect(container.read(storeProvider).cartCount, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    },
  );

  for (final viewport in [
    (size: const Size(320, 568), scale: 1.0),
    (size: const Size(320, 844), scale: 2.0),
    (size: const Size(320, 844), scale: 3.0),
    (size: const Size(390, 844), scale: 1.3),
  ]) {
    testWidgets(
      'sign-in stays usable at ${viewport.size}, text ${viewport.scale}, with keyboard',
      (tester) async {
        tester.view.physicalSize = viewport.size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
        tester.platformDispatcher.textScaleFactorTestValue = viewport.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(appRouterProvider).go('/login');
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const KoyasApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Groceries made simple.'), findsOneWidget);
        final email = find.byKey(const Key('login-email'));
        await tester.ensureVisible(email);
        await tester.enterText(email, 'customer@example.com');
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await tester.pumpAndSettle();
        await tester.ensureVisible(email);
        expect(tester.takeException(), isNull);
        FocusManager.instance.primaryFocus?.unfocus();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        final continueButton = find.byKey(const Key('customer-login'));
        await tester.ensureVisible(continueButton);
        await tester.tap(continueButton);
        await tester.pumpAndSettle();
        expect(container.read(storeProvider).isAuthenticated, isTrue);
        expect(find.byKey(const Key('customer-tab-home')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final viewport in [
    (size: const Size(320, 844), scale: 1.0),
    (size: const Size(320, 844), scale: 2.0),
    (size: const Size(320, 844), scale: 3.0),
    (size: const Size(360, 800), scale: 1.3),
    (size: const Size(390, 844), scale: 1.0),
    (size: const Size(430, 932), scale: 2.0),
    (size: const Size(740, 360), scale: 1.3),
    (size: const Size(768, 1024), scale: 2.0),
  ]) {
    testWidgets(
      'shopping screens fit ${viewport.size}, text ${viewport.scale}',
      (tester) async {
        final errors = <FlutterErrorDetails>[];
        final previousErrorHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          errors.add(details);
          previousErrorHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = previousErrorHandler);
        tester.view.physicalSize = viewport.size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
        tester.platformDispatcher.textScaleFactorTestValue = viewport.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final controller = container.read(storeProvider.notifier)..loginDemo();
        final state = container.read(storeProvider);
        final product = state.products.firstWhere(
          (p) => p.billingName == 'A ATTA MULTI 5KG',
        );
        controller.addToCart(product.id);
        final router = container.read(appRouterProvider)..go('/home');
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const KoyasApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '/home');
        await tester.scrollUntilVisible(
          find.text('SHOP YOUR WAY'),
          160,
          scrollable: find
              .descendant(
                of: find.byType(HomeScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('home-offer-stacked')),
          viewport.size.width < 600 && viewport.scale > 1.4
              ? findsOneWidget
              : findsNothing,
        );
        for (final path in [
          '/categories',
          '/products?category=${product.categoryId}',
          '/product/${product.id}',
          '/cart',
          '/checkout/fulfilment',
          '/checkout/delivery',
          '/checkout/payment',
          '/order/confirmation/${state.orders.first.id}',
          '/order/${state.orders.first.id}',
          '/orders',
          '/profile',
        ]) {
          router.go(path);
          await tester.pumpAndSettle();
          final error = tester.takeException();
          if (error != null) {
            fail(
              '$path: ${errors.isNotEmpty ? errors.last.toString() : error}',
            );
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('home builds visible products lazily while retaining scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(storeProvider.notifier).loginDemo();
    container.read(appRouterProvider).go('/home');
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const KoyasApp()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProductCard).evaluate().length, lessThan(24));
    final scroll = find
        .descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(CustomScrollView),
        )
        .first;
    await tester.drag(scroll, const Offset(0, -1100));
    await tester.pumpAndSettle();
    final built = find.byType(ProductCard).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(24));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'large-text pack picker can reach and add every size above system inset',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 34);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(storeProvider.notifier).loginDemo();
      final state = container.read(storeProvider);
      final product = state.products.firstWhere(
        (p) => p.billingName == 'A ATTA MULTI 5KG',
      );
      final family = ProductVariants.familyFor(
        product: product,
        catalogue: state.products,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
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
      final horizontal = find
          .descendant(
            of: find.byKey(const Key('variant-cards')),
            matching: find.byType(Scrollable),
          )
          .first;
      for (final product in family.variants) {
        final add = find.byKey(Key('variant-add-${product.id}'));
        await tester.scrollUntilVisible(add, 100, scrollable: horizontal);
        await tester.ensureVisible(add);
        await tester.pumpAndSettle();
        expect(tester.getBottomLeft(add).dy, lessThanOrEqualTo(640 - 34));
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(
          container.read(storeProvider).cartQuantities[product.id],
          isNull,
        );
      }
      final confirm = find.byKey(const Key('confirm-variant-selection'));
      expect(tester.getBottomLeft(confirm).dy, lessThanOrEqualTo(640 - 34));
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      for (final product in family.variants) {
        expect(container.read(storeProvider).cartQuantities[product.id], 1);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'reduced motion shows destination without page travel on $platform',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        key: Key('destination'),
                        body: Text('Details'),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.getTopLeft(find.byKey(const Key('destination'))),
          Offset.zero,
        );
        expect(find.text('Details'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('normal iOS page motion retains swipe-back navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: Text('Product details')),
                  ),
                ),
              ),
              child: const Text('Browse'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    expect(find.text('Product details'), findsOneWidget);
    await tester.timedDragFrom(
      const Offset(1, 300),
      const Offset(650, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('Product details'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
