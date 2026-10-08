import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'customer_alert_platform_native.dart'
    if (dart.library.js_interop) 'customer_alert_platform_web.dart'
    as platform;

abstract class CustomerAlertPlatform {
  Future<bool> enable();

  /// Restore an existing opt-in without showing another permission prompt.
  Future<bool> restore() async => false;
  Future<bool> openSettings() async => false;
  Future<bool> show({
    required String title,
    required String body,
    required bool sound,
    required void Function() onOpen,
  });
  void dispose();
}

final customerAlertPlatformFactoryProvider =
    Provider<CustomerAlertPlatform Function()>(
      (ref) => platform.createCustomerAlertPlatform,
    );
