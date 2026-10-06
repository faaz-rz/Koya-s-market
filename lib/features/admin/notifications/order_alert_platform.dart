import 'order_alert_types.dart';
import 'order_alert_platform_stub.dart'
    if (dart.library.js_interop) 'order_alert_platform_web.dart'
    as platform;
export 'order_alert_types.dart';

OrderAlertPlatform createOrderAlertPlatform() =>
    platform.createOrderAlertPlatform();
