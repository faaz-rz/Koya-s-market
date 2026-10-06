import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/admin/admin_app.dart';
import 'package:koyas_supermarket/features/admin/notifications/order_alert_platform.dart';
import 'package:koyas_supermarket/features/admin/notifications/staff_order_alerts.dart';
import 'package:koyas_supermarket/features/orders/models/order.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

class _PreviewAlerts implements OrderAlertPlatform {
  @override
  Future<OrderAlertPermission> enable() async => const OrderAlertPermission(
    sound: true,
    notifications: BrowserAlertPermission.granted,
  );
  @override
  Future<bool> playChime() async => true;
  @override
  bool notify({required int count, required void Function() onOpen}) => true;
  @override
  void badge(int count) {}
  @override
  void dismiss() {}
  @override
  void dispose() {}
}

void main() {
  for (final viewport in [(320.0, 1.3), (390.0, 1.0), (1400.0, 1.0)]) {
    testWidgets('staff alerts at ${viewport.$1}px text ${viewport.$2}', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final font = FontLoader('Manrope')
          ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await Future.wait([font.load(), icons.load()]);
      });
      tester.view.physicalSize = Size(viewport.$1, 1000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = viewport.$2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = ProviderContainer(
        overrides: [
          orderAlertPlatformProvider.overrideWithValue(_PreviewAlerts()),
        ],
      );
      addTearDown(container.dispose);
      const capture = Key('staff-alert-capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: UncontrolledProviderScope(
            container: container,
            child: const KoyasAdminApp(),
          ),
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
      await tester.tap(find.byKey(const Key('admin-enable-order-alerts')));
      await tester.pumpAndSettle();
      final store = container.read(storeProvider), base = store.orders.first;
      final created = store.orders
          .map((o) => o.createdAt)
          .reduce((a, b) => a.isAfter(b) ? a : b)
          .add(const Duration(seconds: 1));
      final order = CustomerOrder(
        id: 'preview-new-order',
        items: base.items,
        fulfilmentType: base.fulfilmentType,
        fulfilmentDate: base.fulfilmentDate,
        slotLabel: base.slotLabel,
        subtotalPaise: base.subtotalPaise,
        deliveryChargePaise: base.deliveryChargePaise,
        discountPaise: base.discountPaise,
        totalPaise: base.totalPaise,
        paymentMethod: base.paymentMethod,
        paymentStatus: base.paymentStatus,
        status: OrderStatus.placed,
        createdAt: created,
      );
      container
          .read(staffOrderAlertsProvider.notifier)
          .observe(store.copyWith(orders: [order, ...store.orders]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(capture))
            .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'outputs/order-alerts/staff-${viewport.$1.toInt()}.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
