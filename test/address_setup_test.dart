import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/app/router/app_router.dart';
import 'package:koyas_supermarket/core/services/network_status.dart';
import 'package:koyas_supermarket/features/checkout/models/checkout_models.dart';
import 'package:koyas_supermarket/features/checkout/screens/address_setup_screen.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';
import 'package:koyas_supermarket/features/notifications/services/push_preferences.dart';
import 'package:koyas_supermarket/features/notifications/services/customer_alert_platform.dart';
import 'package:koyas_supermarket/features/notifications/providers/customer_order_alerts.dart';
import 'customer_order_alerts_test.dart' show FakeAlerts;
import 'push_session_test.dart' show TestPreferences;

class NewCustomerStore extends StoreController {
  void firstCustomer() {
    loginDemo();
    state = state.copyWith(addresses: [], selectedAddressId: '');
  }
}

Future<ProviderContainer> open(
  WidgetTester tester, {
  required Future<CustomerAddress> Function(CustomerAddress) save,
  double scale = 1,
  double width = 390,
  FakeAlerts? alerts,
  TestPreferences? notificationPreferences,
  bool askNotifications = false,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = ProviderContainer(
    overrides: [
      storeProvider.overrideWith(NewCustomerStore.new),
      firstAddressSaverProvider.overrideWithValue(save),
      firstLoginNotificationPromptProvider.overrideWithValue(askNotifications),
      pushPreferencesProvider.overrideWithValue(
        notificationPreferences ?? TestPreferences(),
      ),
      if (alerts != null)
        customerAlertPlatformFactoryProvider.overrideWithValue(() => alerts),
    ],
  );
  addTearDown(c.dispose);
  (c.read(storeProvider.notifier) as NewCustomerStore).firstCustomer();
  c.read(appRouterProvider).go('/home');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 844),
          textScaler: TextScaler.linear(scale),
        ),
        child: const KoyasApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

Future<void> fill(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('address-line')),
    '12 Market Road',
  );
  await tester.enterText(find.byKey(const Key('address-pincode')), '500008');
  await tester.ensureVisible(find.byKey(const Key('save-address')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'first sign-in asks for notifications once; declining leaves address setup and shopping usable',
    (tester) async {
      final fake = FakeAlerts()..permission = false;
      final preferences = TestPreferences();
      final c = await open(
        tester,
        save: (address) async => address,
        alerts: fake,
        notificationPreferences: preferences,
        askNotifications: true,
      );
      expect(fake.enableRequests, 1);
      expect(preferences.values['demo-customer']!.prompted, true);
      await c.read(customerOrderAlertsProvider.notifier).promptForFirstLogin();
      expect(fake.enableRequests, 1);
      await fill(tester);
      await tester.tap(find.byKey(const Key('save-address')));
      await tester.pumpAndSettle();
      expect(
        c.read(appRouterProvider).routeInformationProvider.value.uri.path,
        '/home',
      );
      expect(c.read(customerOrderAlertsProvider).enabled, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'first customer cannot bypass address setup; confirmed save sets default and returns home',
    (tester) async {
      var saves = 0;
      final c = await open(
        tester,
        save: (a) async {
          saves++;
          return a.copyWith(isDefault: true);
        },
      );
      final router = c.read(appRouterProvider);
      for (final route in [
        '/home',
        '/products',
        '/cart',
        '/checkout/payment',
        '/order/unknown',
      ]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/address/setup',
        );
      }
      await tester.ensureVisible(find.byKey(const Key('save-address')));
      await tester.tap(find.byKey(const Key('save-address')));
      await tester.pumpAndSettle();
      expect(saves, 0);
      await fill(tester);
      await tester.tap(find.byKey(const Key('save-address')));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(c.read(storeProvider).addresses.single.isDefault, true);
      expect(router.routeInformationProvider.value.uri.path, '/home');
      router.go('/profile');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/profile');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'offline save remains on setup, keeps typed address, and can retry',
    (tester) async {
      var attempts = 0;
      final c = await open(
        tester,
        save: (a) async {
          if (++attempts == 1) throw const NoInternetException();
          return a;
        },
      );
      await fill(tester);
      await tester.tap(find.byKey(const Key('save-address')));
      await tester.pumpAndSettle();
      expect(c.read(storeProvider).addresses, isEmpty);
      expect(find.text(noInternetMessage), findsOneWidget);
      expect(
        (tester.widget<TextFormField>(
          find.byKey(const Key('address-line')),
        )).controller!.text,
        '12 Market Road',
      );
      await tester.ensureVisible(find.byKey(const Key('save-address')));
      await tester.tap(find.byKey(const Key('save-address')));
      await tester.pumpAndSettle();
      expect(c.read(storeProvider).addresses, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'duplicate save is blocked and a late response cannot populate another session',
    (tester) async {
      final pending = Completer<CustomerAddress>();
      CustomerAddress? submitted;
      var saves = 0;
      final c = await open(
        tester,
        save: (a) {
          saves++;
          submitted = a;
          return pending.future;
        },
      );
      await fill(tester);
      await tester.tap(find.byKey(const Key('save-address')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('save-address')));
      await tester.pump();
      expect(saves, 1);
      c.read(storeProvider.notifier).logout();
      await tester.pumpAndSettle();
      pending.complete(submitted!);
      await tester.pumpAndSettle();
      expect(c.read(storeProvider).isAuthenticated, false);
      expect(
        c.read(appRouterProvider).routeInformationProvider.value.uri.path,
        '/login',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('returning customers and staff do not need first-address setup', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(storeProvider.notifier).loginDemo();
    expect(c.read(storeProvider).needsAddressSetup, false);
    c.read(storeProvider.notifier).loginDemo(isAdmin: true);
    expect(c.read(storeProvider).needsAddressSetup, false);
  });
}
