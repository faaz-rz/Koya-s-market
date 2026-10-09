import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/features/notifications/providers/customer_order_alerts.dart';
import 'package:koyas_supermarket/features/notifications/services/customer_alert_platform.dart';
import 'package:koyas_supermarket/features/orders/models/order.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';
import 'package:koyas_supermarket/features/notifications/services/push_preferences.dart';
import 'push_session_test.dart' show TestPreferences;

class FakeAlerts extends CustomerAlertPlatform {
  final messages = <String>[];
  final sounds = <bool>[];
  bool disposed = false;
  bool permission = true;
  int enableRequests = 0;
  int restores = 0;
  Future<bool>? permissionResult;
  void Function()? open;
  @override
  Future<bool> enable() {
    enableRequests++;
    return permissionResult ?? Future.value(permission);
  }

  @override
  Future<bool> restore() async {
    restores++;
    return permission;
  }

  @override
  Future<bool> show({
    required String title,
    required String body,
    required bool sound,
    required void Function() onOpen,
  }) async {
    messages.add('$title $body');
    sounds.add(sound);
    open = onOpen;
    return true;
  }

  @override
  void dispose() => disposed = true;
}

class AlertTestStore extends StoreController {
  void updateOrderStatus(String id, OrderStatus status) {
    state = state.copyWith(
      orders: state.orders
          .map((o) => o.id == id ? o.copyWith(status: status) : o)
          .toList(),
    );
  }
}

void main() {
  testWidgets(
    'saved opt-in restores system notifications and mute without asking again',
    (tester) async {
      final fake = FakeAlerts();
      final preferences = TestPreferences()
        ..values['demo-customer'] = const PushPreference(
          enabled: true,
          sound: false,
        );
      final c = ProviderContainer(
        overrides: [
          storeProvider.overrideWith(AlertTestStore.new),
          pushPreferencesProvider.overrideWithValue(preferences),
          customerAlertPlatformFactoryProvider.overrideWithValue(() => fake),
        ],
      );
      addTearDown(c.dispose);
      c.read(storeProvider.notifier).loginDemo();
      c.read(appRouterProvider).go('/orders');
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const KoyasApp()),
      );
      await tester.pumpAndSettle();
      expect(fake.restores, 1);
      expect(c.read(customerOrderAlertsProvider).enabled, true);
      final controller = c.read(storeProvider.notifier) as AlertTestStore;
      controller.updateOrderStatus(
        c.read(storeProvider).orders.first.id,
        OrderStatus.readyForPickup,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(fake.messages, hasLength(1));
      expect(fake.sounds, [false]);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Ready for pickup'), findsWidgets);
      c.read(storeProvider.notifier).logout();
      await tester.pumpAndSettle();
      expect(fake.disposed, true);
      expect(c.read(customerOrderAlertsProvider).enabled, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'history is silent; pickup, delivery and completion alert once even after replay',
    () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(storeProvider.notifier).loginDemo();
      final base = c.read(storeProvider).orders.first;
      final tracker = CustomerStatusTracker();
      expect(tracker.observe([base]), isEmpty);
      final ready = base.copyWith(status: OrderStatus.readyForPickup);
      expect(
        tracker.observe([ready]).single.status,
        OrderStatus.readyForPickup,
      );
      expect(tracker.observe([ready]), isEmpty);
      expect(tracker.observe([base]), isEmpty);
      expect(tracker.observe([ready]), isEmpty);
      expect(
        tracker
            .observe([base.copyWith(status: OrderStatus.outForDelivery)])
            .single
            .status,
        OrderStatus.outForDelivery,
      );
      expect(
        tracker
            .observe([base.copyWith(status: OrderStatus.delivered)])
            .single
            .status,
        OrderStatus.delivered,
      );
    },
  );

  testWidgets(
    'live banner persists across routes; burst alerts once, mute works, click opens owned order',
    (tester) async {
      final fake = FakeAlerts();
      final c = ProviderContainer(
        overrides: [
          storeProvider.overrideWith(AlertTestStore.new),
          pushPreferencesProvider.overrideWithValue(TestPreferences()),
          customerAlertPlatformFactoryProvider.overrideWithValue(() => fake),
        ],
      );
      addTearDown(c.dispose);
      c.read(storeProvider.notifier).loginDemo();
      c.read(appRouterProvider).go('/orders');
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const KoyasApp()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('enable-customer-alerts')).first);
      await tester.pumpAndSettle();
      final initial = c.read(storeProvider);
      final controller = c.read(storeProvider.notifier) as AlertTestStore;
      controller.updateOrderStatus(
        initial.orders[0].id,
        OrderStatus.readyForPickup,
      );
      controller.updateOrderStatus(
        initial.orders[1].id,
        OrderStatus.outForDelivery,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(fake.messages.length, 1);
      expect(fake.sounds, [true]);
      expect(find.text('2 order updates'), findsOneWidget);
      c.read(appRouterProvider).go('/profile');
      await tester.pumpAndSettle();
      expect(find.text('2 order updates'), findsOneWidget);
      fake.open!();
      await tester.pumpAndSettle();
      expect(
        c.read(appRouterProvider).routeInformationProvider.value.uri.path,
        '/order/${initial.orders[1].id}',
      );
      expect(c.read(customerOrderAlertsProvider).updates, isEmpty);
      c.read(customerOrderAlertsProvider.notifier).mute(true);
      controller.updateOrderStatus(initial.orders[1].id, OrderStatus.delivered);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(fake.sounds, [true, false]);
      expect(
        fake.messages.last,
        contains('Order #${initial.orders[1].customerDisplayNumber}:'),
      );
      controller.logout();
      await tester.pumpAndSettle();
      expect(fake.disposed, true);
      expect(c.read(customerOrderAlertsProvider).updates, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'permission denied preserves updates; stale permission after logout and same-user login is ignored',
    () async {
      final permission = Completer<bool>();
      final fake = FakeAlerts()..permissionResult = permission.future;
      final c = ProviderContainer(
        overrides: [
          customerAlertPlatformFactoryProvider.overrideWithValue(() => fake),
        ],
      );
      addTearDown(c.dispose);
      c.read(storeProvider.notifier).loginDemo();
      final alerts = c.read(customerOrderAlertsProvider.notifier);
      alerts.observe(c.read(storeProvider));
      final waiting = alerts.enable();
      c.read(storeProvider.notifier).logout();
      alerts.observe(c.read(storeProvider));
      c.read(storeProvider.notifier).loginDemo();
      alerts.observe(c.read(storeProvider));
      permission.complete(true);
      await waiting;
      expect(c.read(customerOrderAlertsProvider).enabled, false);
      final store = c.read(storeProvider);
      alerts.observe(
        store.copyWith(
          orders: [
            store.orders.first.copyWith(status: OrderStatus.readyForPickup),
          ],
        ),
      );
      expect(c.read(customerOrderAlertsProvider).updates, hasLength(1));
      expect(fake.messages, isEmpty);
    },
  );
}
