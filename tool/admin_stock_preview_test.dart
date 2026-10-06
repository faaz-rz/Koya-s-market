// Visual QA: flutter test --no-pub tool/admin_stock_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/admin/admin_app.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

void main() {
  for (final width in [390.0, 1400.0]) {
    testWidgets('inventory quantity editor at ${width}px', (tester) async {
      await tester.runAsync(() async {
        final font = FontLoader('Manrope')
          ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await Future.wait([font.load(), icons.load()]);
      });
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const capture = Key('inventory-capture');
      await tester.pumpWidget(
        const RepaintBoundary(
          key: capture,
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
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      final product = container.read(storeProvider).products.first;
      await tester.enterText(
        find.byKey(const Key('admin-product-search')),
        product.name,
      );
      await tester.pumpAndSettle();
      final input = find.byKey(Key('admin-stock-quantity-${product.id}'));
      await tester.ensureVisible(input);
      await tester.enterText(input, '500');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('outputs/inventory/stock-${width.toInt()}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
