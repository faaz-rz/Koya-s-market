import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/admin/admin_app.dart';
import 'package:koyas_supermarket/admin/router/admin_router.dart';
import 'package:koyas_supermarket/features/admin/notifications/order_alert_platform.dart';
import 'package:koyas_supermarket/features/admin/notifications/staff_order_alerts.dart';
import 'package:koyas_supermarket/features/orders/models/order.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';

class _Delivery implements OrderAlertPlatform {
  int sounds = 0, closed = 0;
  final counts = <int>[];
  final badges = <int>[];
  void Function()? onOpen;
  Future<OrderAlertPermission>? enableResult;
  bool canPlay = true;
  @override
  Future<OrderAlertPermission> enable() =>
      enableResult ??
      Future.value(
        const OrderAlertPermission(
          sound: true,
          notifications: BrowserAlertPermission.granted,
        ),
      );
  @override
  Future<bool> playChime() async {
    sounds++;
    return canPlay;
  }

  @override
  bool notify({required int count, required void Function() onOpen}) {
    counts.add(count);
    this.onOpen = onOpen;
    return true;
  }

  @override
  void badge(int count) => badges.add(count);
  @override
  void dismiss() => closed++;
  @override
  void dispose() => closed++;
}

CustomerOrder _newOrder(
  StoreState store,
  String id, {
  OrderStatus status = OrderStatus.placed,
  DateTime? createdAt,
}) {
  final base = store.orders.first;
  final date =
      createdAt ??
      store.orders
          .map((o) => o.createdAt)
          .reduce((a, b) => a.isAfter(b) ? a : b)
          .add(const Duration(seconds: 1));
  return CustomerOrder(
    id: id,
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
    status: status,
    createdAt: date,
    reference: 'KOY123',
  );
}

void main() {
  test(
    'initial history is silent; new orders deduplicate across snapshots and status changes',
    () async {
      final delivery = _Delivery();
      final container = ProviderContainer(
        overrides: [orderAlertPlatformProvider.overrideWithValue(delivery)],
      );
      addTearDown(container.dispose);
      container.read(storeProvider.notifier).loginDemo(isAdmin: true);
      final store = container.read(storeProvider);
      final alerts = container.read(staffOrderAlertsProvider.notifier);
      alerts.observe(store);
      expect(delivery.sounds, 0);
      expect(delivery.counts, isEmpty);
      await alerts.enable();
      expect(delivery.sounds, 1); // Explicit enable/test chime only.
      final first = _newOrder(store, 'fresh-a'),
          second = _newOrder(store, 'fresh-b');
      final changed = store.copyWith(orders: [first, second, ...store.orders]);
      alerts.observe(changed);
      await Future<void>.delayed(Duration.zero);
      expect(delivery.sounds, 2);
      expect(delivery.counts, [2]);
      expect(container.read(staffOrderAlertsProvider).pending, {
        'fresh-a',
        'fresh-b',
      });
      alerts.observe(changed);
      expect(delivery.counts, [2]);
      alerts.observe(
        changed.copyWith(
          orders: [
            first.copyWith(status: OrderStatus.confirmed),
            second.copyWith(status: OrderStatus.cancelled),
            ...store.orders,
          ],
        ),
      );
      expect(container.read(staffOrderAlertsProvider).pending, isEmpty);
      expect(delivery.badges.last, 0);
    },
  );

  test(
    'muting, denied permission and an unplayable chime preserve in-app alerts',
    () async {
      final delivery = _Delivery()
        ..enableResult = Future.value(
          const OrderAlertPermission(
            sound: true,
            notifications: BrowserAlertPermission.denied,
          ),
        );
      final container = ProviderContainer(
        overrides: [orderAlertPlatformProvider.overrideWithValue(delivery)],
      );
      addTearDown(container.dispose);
      container.read(storeProvider.notifier).loginDemo(isAdmin: true);
      final store = container.read(storeProvider),
          alerts = container.read(staffOrderAlertsProvider.notifier);
      alerts.observe(store);
      await alerts.enable();
      alerts.mute();
      alerts.observe(
        store.copyWith(orders: [_newOrder(store, 'fresh'), ...store.orders]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(delivery.sounds, 1);
      expect(delivery.counts, isEmpty);
      expect(container.read(staffOrderAlertsProvider).pending, {'fresh'});
      delivery.canPlay = false;
      await alerts.testSound();
      expect(
        container.read(staffOrderAlertsProvider).note,
        contains('Sound is blocked'),
      );
      expect(container.read(staffOrderAlertsProvider).pending, {'fresh'});
    },
  );

  test(
    'logout during browser permission request cannot enable or open staff alerts',
    () async {
      final pending = Completer<OrderAlertPermission>();
      final delivery = _Delivery()..enableResult = pending.future;
      final container = ProviderContainer(
        overrides: [orderAlertPlatformProvider.overrideWithValue(delivery)],
      );
      addTearDown(container.dispose);
      container.read(storeProvider.notifier).loginDemo(isAdmin: true);
      final alerts = container.read(staffOrderAlertsProvider.notifier);
      alerts.observe(container.read(storeProvider));
      final enabling = alerts.enable();
      container.read(storeProvider.notifier).logout();
      alerts.observe(container.read(storeProvider));
      // Even a new login with the same user ID must reject the old request.
      container.read(storeProvider.notifier).loginDemo(isAdmin: true);
      alerts.observe(container.read(storeProvider));
      pending.complete(
        const OrderAlertPermission(
          sound: true,
          notifications: BrowserAlertPermission.granted,
        ),
      );
      await enabling;
      expect(container.read(staffOrderAlertsProvider).enabled, false);
      expect(delivery.sounds, 0);
    },
  );

  test(
    'reconnect catches a missed new order but historical/replayed records stay silent',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(storeProvider.notifier).loginDemo(isAdmin: true);
      final store = container.read(storeProvider), tracker = NewOrderTracker();
      expect(tracker.observe('staff', store.orders), isEmpty);
      final recent = _newOrder(store, 'missed');
      expect(
        tracker.observe('staff', [recent, ...store.orders]).map((o) => o.id),
        ['missed'],
      );
      tracker.observe('staff', store.orders);
      expect(tracker.observe('staff', [recent, ...store.orders]), isEmpty);
      expect(
        tracker.observe('another-staff', [recent, ...store.orders]),
        isEmpty,
      );
    },
  );

  test(
    'an order that commits late is identified by ID even when its creation timestamp is older',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(storeProvider.notifier).loginDemo(isAdmin: true);
      final store = container.read(storeProvider), tracker = NewOrderTracker();
      tracker.observe('staff', store.orders);
      final late = _newOrder(
        store,
        'late-commit',
        createdAt: store.orders.first.createdAt.subtract(
          const Duration(minutes: 1),
        ),
      );
      expect(
        tracker.observe('staff', [late, ...store.orders]).map((o) => o.id),
        ['late-commit'],
      );
      expect(tracker.observe('staff', [late, ...store.orders]), isEmpty);
    },
  );

  testWidgets(
    'banner and sound controls persist across staff routes and disappear on sign-out',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final delivery = _Delivery();
      final container = ProviderContainer(
        overrides: [orderAlertPlatformProvider.overrideWithValue(delivery)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const KoyasAdminApp(),
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
      final store = container.read(storeProvider);
      container
          .read(storeProvider.notifier)
          .hydrateFromBackend(
            profile: store.profile!,
            categories: store.categories,
            products: store.products,
            addresses: store.addresses,
            orders: [_newOrder(store, 'new-order'), ...store.orders],
            offers: store.offers,
            pickupSlots: store.pickupSlots,
            deliverySlots: store.deliverySlots,
            isAdmin: true,
            serviceablePincodes: store.serviceablePincodes,
            minimumOrderPaise: store.minimumOrderPaise,
            baseDeliveryChargePaise: store.baseDeliveryChargePaise,
            freeDeliveryThresholdPaise: store.freeDeliveryThresholdPaise,
            pickupEnabled: store.pickupEnabled,
            deliveryEnabled: store.deliveryEnabled,
            cashOnDeliveryEnabled: store.cashOnDeliveryEnabled,
          );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-new-order-banner')), findsOneWidget);
      expect(delivery.counts, [1]);
      container.read(adminRouterProvider).go('/inventory');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-new-order-banner')), findsOneWidget);
      expect(find.byKey(const Key('admin-test-order-sound')), findsOneWidget);
      expect(delivery.counts, [1]);
      container.read(adminRouterProvider).go('/orders');
      await tester.pumpAndSettle();
      final filterChip = find.byWidgetPredicate(
        (w) =>
            w is Chip && w.label is Text && (w.label as Text).data == 'Active',
      );
      await tester.ensureVisible(filterChip);
      await tester.tap(filterChip);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin-view-new-orders')));
      await tester.pumpAndSettle();
      expect(find.text('Order queue'), findsOneWidget);
      final activeFilter = find.byWidgetPredicate(
        (w) =>
            w is Chip && w.label is Text && (w.label as Text).data == 'Active',
      );
      expect(activeFilter, findsOneWidget);
      expect(find.byKey(const Key('admin-new-order-banner')), findsNothing);
      container.read(storeProvider.notifier).logout();
      await tester.pumpAndSettle();
      expect(container.read(staffOrderAlertsProvider).pending, isEmpty);
      expect(container.read(staffOrderAlertsProvider).enabled, false);
    },
  );
}
