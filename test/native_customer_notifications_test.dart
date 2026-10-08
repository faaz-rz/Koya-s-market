import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:koyas_supermarket/features/notifications/services/customer_alert_platform_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Android restore does not prompt and posts an expanded public notification without expiry',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'initialize' ||
                call.method == 'areNotificationsEnabled') {
              return true;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final alerts = NativeCustomerAlerts();
      expect(await alerts.restore(), true);
      expect(
        calls.any((c) => c.method == 'requestNotificationsPermission'),
        false,
      );
      expect(
        await alerts.show(
          title: 'Ready for pickup',
          body: 'Your order is ready to collect.',
          sound: true,
          onOpen: () {},
        ),
        true,
      );
      final arguments = Map<String, dynamic>.from(
        calls.singleWhere((c) => c.method == 'show').arguments as Map,
      );
      final details = Map<String, dynamic>.from(
        arguments['platformSpecifics'] as Map,
      );
      expect(details['visibility'], 1);
      expect(details['importance'], 4);
      expect(details['timeoutAfter'], isNull);
      expect(details['autoCancel'], true);
      expect(details['styleInformation'], isA<Map>());
      alerts.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );
}
