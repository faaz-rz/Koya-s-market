import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/app/app.dart';
import 'package:koyas_supermarket/features/notifications/data/notification_repository.dart';
import 'package:koyas_supermarket/features/notifications/providers/customer_order_alerts.dart';
import 'package:koyas_supermarket/features/notifications/providers/push_session.dart';
import 'package:koyas_supermarket/features/notifications/providers/startup_notification_permission.dart';
import 'package:koyas_supermarket/features/notifications/services/customer_alert_platform.dart';
import 'package:koyas_supermarket/features/notifications/services/push_gateway.dart';
import 'package:koyas_supermarket/features/notifications/services/push_preferences.dart';
import 'package:koyas_supermarket/features/store/providers/store_provider.dart';
import 'customer_order_alerts_test.dart' show FakeAlerts;
import 'push_session_test.dart' show TestPreferences, TestGateway, TestRegistry;

class MemoryPermissionStorage extends StartupNotificationPermissionStorage {
  SavedNotificationPermission value = const SavedNotificationPermission();
  @override
  Future<SavedNotificationPermission> read() async => value;
  @override
  Future<void> write(SavedNotificationPermission next) async => value = next;
}

class FirstLaunchAlerts extends FakeAlerts {
  FirstLaunchAlerts() {
    permission = false;
  }
  bool grantRequest = true;
  @override
  Future<bool> enable() async {
    enableRequests++;
    permission = await (permissionResult ?? Future.value(grantRequest));
    return permission;
  }
}

class WaitingPermissionCheck extends FakeAlerts {
  final result = Completer<bool>();
  @override
  Future<bool> restore() => result.future;
}

class UnavailablePermissionStorage extends MemoryPermissionStorage {
  @override
  Future<SavedNotificationPermission> read() async =>
      throw StateError('Device preferences unavailable');
}

ProviderContainer setup(
  FirstLaunchAlerts platform,
  MemoryPermissionStorage storage, {
  TestPreferences? preferences,
  TestGateway? gateway,
  TestRegistry? registry,
}) => ProviderContainer(
  overrides: [
    startupNotificationPromptEnabledProvider.overrideWithValue(true),
    startupNotificationStorageProvider.overrideWithValue(storage),
    customerAlertPlatformFactoryProvider.overrideWithValue(() => platform),
    pushPreferencesProvider.overrideWithValue(preferences ?? TestPreferences()),
    if (gateway != null) pushGatewayProvider.overrideWithValue(gateway),
    if (registry != null)
      pushDeviceRegistryProvider.overrideWithValue(registry),
  ],
);

void main() {
  testWidgets(
    'a startup preference failure does not suppress an existing notification opt-in',
    (tester) async {
      final platform = FakeAlerts();
      final preferences = TestPreferences()
        ..values['demo-customer'] = const PushPreference(enabled: true);
      final c = ProviderContainer(
        overrides: [
          startupNotificationPromptEnabledProvider.overrideWithValue(true),
          startupNotificationStorageProvider.overrideWithValue(
            UnavailablePermissionStorage(),
          ),
          customerAlertPlatformFactoryProvider.overrideWithValue(
            () => platform,
          ),
          pushPreferencesProvider.overrideWithValue(preferences),
        ],
      );
      addTearDown(c.dispose);
      c.read(storeProvider.notifier).loginDemo();
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const KoyasApp()),
      );
      await tester.pumpAndSettle();
      expect(c.read(customerOrderAlertsProvider).enabled, true);
      expect(platform.enableRequests, 0);
      expect(preferences.values['demo-customer']!.enabled, true);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'returning customer notification presenter initializes after the startup permission check',
    (tester) async {
      final initial = WaitingPermissionCheck(), account = FakeAlerts();
      var presenters = 0;
      final preferences = TestPreferences()
        ..values['demo-customer'] = const PushPreference(
          enabled: true,
          sound: false,
        );
      final c = ProviderContainer(
        overrides: [
          startupNotificationPromptEnabledProvider.overrideWithValue(true),
          startupNotificationStorageProvider.overrideWithValue(
            MemoryPermissionStorage()
              ..value = const SavedNotificationPermission(
                prompted: true,
                granted: true,
              ),
          ),
          customerAlertPlatformFactoryProvider.overrideWithValue(
            () => ++presenters == 1 ? initial : account,
          ),
          pushPreferencesProvider.overrideWithValue(preferences),
        ],
      );
      addTearDown(c.dispose);
      c.read(storeProvider.notifier).loginDemo();
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const KoyasApp()),
      );
      await tester.pumpAndSettle();
      expect(presenters, 1);
      initial.result.complete(true);
      await tester.pumpAndSettle();
      expect(presenters, 2);
      expect(c.read(customerOrderAlertsProvider).enabled, true);
      expect(c.read(customerOrderAlertsProvider).sound, false);
      expect(account.enableRequests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'allowing startup notifications for an existing customer with an address preserves mute settings',
    (tester) async {
      final platform = FirstLaunchAlerts(), storage = MemoryPermissionStorage();
      final preferences = TestPreferences()
        ..values['demo-customer'] = const PushPreference(
          sound: false,
          prompted: true,
        );
      final c = setup(platform, storage, preferences: preferences);
      addTearDown(c.dispose);
      c.read(storeProvider.notifier).loginDemo();
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const KoyasApp()),
      );
      await tester.pumpAndSettle();
      expect(c.read(storeProvider).addresses, isNotEmpty);
      expect(platform.enableRequests, 1);
      expect(c.read(customerOrderAlertsProvider).enabled, true);
      expect(c.read(customerOrderAlertsProvider).sound, false);
      expect(preferences.values['demo-customer']!.sound, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'permission is requested on startup before login; allow activates the signed-in account without a second OS request',
    (tester) async {
      final platform = FirstLaunchAlerts(), storage = MemoryPermissionStorage();
      final gateway = TestGateway(),
          registry = TestRegistry(),
          preferences = TestPreferences();
      final c = setup(
        platform,
        storage,
        gateway: gateway,
        registry: registry,
        preferences: preferences,
      );
      addTearDown(c.dispose);
      addTearDown(() async {
        await gateway.refresh.close();
        await gateway.messages.close();
        await gateway.taps.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const KoyasApp()),
      );
      await tester.pumpAndSettle();
      expect(c.read(storeProvider).isAuthenticated, false);
      expect(platform.enableRequests, 1);
      expect(storage.value.granted, true);
      expect(registry.registrations, isEmpty);
      c.read(storeProvider.notifier).loginDemo();
      await tester.pumpAndSettle();
      await c.read(pushSessionProvider).settled;
      expect(c.read(customerOrderAlertsProvider).enabled, true);
      expect(preferences.values['demo-customer']!.enabled, true);
      expect(registry.registrations, contains('demo-customer:device-token'));
      expect(gateway.prompts, 0);
      expect(platform.enableRequests, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'decline is remembered across launches; already allowed devices are checked without another prompt',
    () async {
      final platform = FirstLaunchAlerts()..grantRequest = false;
      final storage = MemoryPermissionStorage();
      var c = setup(platform, storage);
      await Future.wait([
        c.read(startupNotificationPermissionProvider.notifier).start(),
        c.read(startupNotificationPermissionProvider.notifier).start(),
      ]);
      expect(platform.enableRequests, 1);
      expect(storage.value.prompted, true);
      c.dispose();
      c = setup(platform, storage);
      await c.read(startupNotificationPermissionProvider.notifier).start();
      expect(platform.enableRequests, 1);
      c.dispose();
      platform.permission = true;
      c = setup(platform, storage);
      await c.read(startupNotificationPermissionProvider.notifier).start();
      expect(platform.enableRequests, 1);
      expect(c.read(startupNotificationPermissionProvider).newConsent, true);
      c.dispose();
    },
  );

  testWidgets(
    'a late permission response after logout cannot register a signed-out device',
    (tester) async {
      final response = Completer<bool>();
      final platform = FirstLaunchAlerts()..permissionResult = response.future;
      final storage = MemoryPermissionStorage(),
          gateway = TestGateway(),
          registry = TestRegistry();
      final c = setup(platform, storage, gateway: gateway, registry: registry);
      addTearDown(c.dispose);
      addTearDown(() async {
        await gateway.refresh.close();
        await gateway.messages.close();
        await gateway.taps.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const KoyasApp()),
      );
      await tester.pumpAndSettle();
      c.read(storeProvider.notifier).loginDemo();
      await tester.pumpAndSettle();
      c.read(storeProvider.notifier).logout();
      await tester.pumpAndSettle();
      response.complete(true);
      await tester.pumpAndSettle();
      await c.read(pushSessionProvider).settled;
      expect(registry.registrations, isEmpty);
      expect(c.read(customerOrderAlertsProvider).enabled, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
