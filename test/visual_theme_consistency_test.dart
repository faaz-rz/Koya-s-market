import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/core/theme/app_colors.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance(), b = background.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

void main() {
  for (final palette in [AppPalette.light, AppPalette.dark]) {
    test(
      'text and actions have readable contrast in ${palette.isDark ? 'dark' : 'light'} appearance',
      () {
        for (final background in [
          palette.surface,
          palette.canvas,
          palette.mint,
          palette.peach,
          palette.surfaceMuted,
        ]) {
          for (final foreground in [palette.ink, palette.inkSecondary]) {
            expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
          }
        }
        for (final background in [
          palette.brand600,
          palette.brand500,
          palette.offer,
          palette.error,
        ]) {
          expect(
            contrast(palette.onBrand, background),
            greaterThanOrEqualTo(4.5),
          );
        }
        for (final pair in [
          (palette.brand700, palette.brandSoft),
          (palette.error, palette.errorSoft),
          (palette.warning, palette.warningSoft),
          (palette.success, palette.successSoft),
          (palette.info, palette.infoSoft),
        ]) {
          expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
        }
      },
    );
  }

  testWidgets(
    'system appearance changes keep the cart and apply to routes and dialogs',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(storeProvider.notifier)..loginDemo();
      final store = container.read(storeProvider);
      final product = store.products.firstWhere((p) => p.isAvailable);
      controller.addToCart(product.id);
      final router = container.read(appRouterProvider)..go('/cart');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const KoyasApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Your cart'))).brightness,
        Brightness.light,
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Your cart'))).brightness,
        Brightness.dark,
      );
      expect(container.read(storeProvider).cartQuantities[product.id], 1);
      for (final path in [
        '/checkout/fulfilment',
        '/checkout/payment',
        '/order/${store.orders.first.id}',
        '/profile',
      ]) {
        router.go(path);
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(Scaffold).last);
        expect(Theme.of(context).brightness, Brightness.dark, reason: path);
        expect(
          AppColors.of(context).surface,
          AppPalette.dark.surface,
          reason: path,
        );
        expect(tester.takeException(), isNull, reason: path);
      }
      await tester.tap(find.byTooltip('Edit profile'));
      await tester.pumpAndSettle();
      final dialog = tester.element(find.byType(AlertDialog));
      expect(
        Theme.of(dialog).dialogTheme.backgroundColor,
        AppPalette.dark.surface,
      );
      expect(Theme.of(dialog).textTheme.bodyMedium?.color, AppPalette.dark.ink);
      expect(container.read(storeProvider).cartQuantities[product.id], 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
