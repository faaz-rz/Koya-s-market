import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/core/theme/appearance_provider.dart';
import 'package:koyas_supermarket/core/theme/app_colors.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

class MemoryAppearance extends AppearanceStorage {
  ThemeMode mode = ThemeMode.system;
  Completer<ThemeMode>? pendingRead;
  @override
  Future<ThemeMode> read() async =>
      pendingRead == null ? mode : pendingRead!.future;
  @override
  Future<void> write(ThemeMode value) async => mode = value;
}

void main() {
  test(
    'saved choice restores in a new app session; stale reads cannot overwrite a new choice',
    () async {
      final storage = MemoryAppearance()..pendingRead = Completer<ThemeMode>();
      final container = ProviderContainer(
        overrides: [appearanceStorageProvider.overrideWithValue(storage)],
      );
      container.read(appearanceProvider);
      await container.read(appearanceProvider.notifier).select(ThemeMode.dark);
      storage.pendingRead!.complete(ThemeMode.light);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(appearanceProvider), ThemeMode.dark);
      container.dispose();
      storage.pendingRead = null;
      final restarted = ProviderContainer(
        overrides: [appearanceStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(restarted.dispose);
      restarted.read(appearanceProvider);
      await Future<void>.delayed(Duration.zero);
      expect(restarted.read(appearanceProvider), ThemeMode.dark);
    },
  );

  testWidgets(
    'Profile appearance overrides the device across routes without losing cart or authentication',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final storage = MemoryAppearance();
      final c = ProviderContainer(
        overrides: [appearanceStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(c.dispose);
      final controller = c.read(storeProvider.notifier)..loginDemo();
      final product = c
          .read(storeProvider)
          .products
          .firstWhere((p) => p.isAvailable);
      controller.addToCart(product.id);
      final router = c.read(appRouterProvider)..go('/profile');
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const KoyasApp()),
      );
      await tester.pumpAndSettle();
      final selector = find.byKey(const Key('appearance-setting'));
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appearance-dark')));
      await tester.pumpAndSettle();
      expect(storage.mode, ThemeMode.dark);
      for (final path in [
        '/home',
        '/products',
        '/cart',
        '/checkout/fulfilment',
        '/profile',
      ]) {
        router.go(path);
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(Scaffold).last);
        expect(Theme.of(context).brightness, Brightness.dark, reason: path);
        expect(AppColors.of(context).surface, AppPalette.dark.surface);
        expect(tester.takeException(), isNull, reason: path);
      }
      expect(c.read(storeProvider).cartQuantities[product.id], 1);
      expect(c.read(storeProvider).isAuthenticated, true);
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appearance-light')));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(selector)).brightness, Brightness.light);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
