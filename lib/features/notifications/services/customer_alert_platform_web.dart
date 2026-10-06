import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../../admin/notifications/order_alert_platform_web.dart';
import '../../admin/notifications/order_alert_types.dart';
import 'customer_alert_platform.dart';

CustomerAlertPlatform createCustomerAlertPlatform() => WebCustomerAlerts();

class WebCustomerAlerts implements CustomerAlertPlatform {
  final _audio = BrowserOrderAlerts();
  web.Notification? _notification;
  bool _disposed = false;
  bool _permission = false;
  bool _sound = false;
  @override
  Future<bool> enable() async {
    final permission = await _audio.enable();
    _permission = permission.notifications == BrowserAlertPermission.granted;
    _sound = permission.sound;
    return !_disposed && (_permission || _sound);
  }

  @override
  Future<bool> show({
    required String title,
    required String body,
    required bool sound,
    required void Function() onOpen,
  }) async {
    if (_disposed) return false;
    bool shown = false;
    if (_permission) {
      try {
        _notification?.close();
        final notification = web.Notification(
          title,
          web.NotificationOptions(
            body: body,
            tag: 'koyas-customer-order',
            icon: '/icons/Icon-192.png',
            silent: true,
          ),
        );
        notification.onclick = ((web.Event _) {
          if (!_disposed) {
            web.window.focus();
            notification.close();
            onOpen();
          }
        }).toJS;
        _notification = notification;
        shown = true;
      } catch (_) {}
    }
    if (sound && _sound) shown = await _audio.playChime() || shown;
    return shown;
  }

  @override
  void dispose() {
    _disposed = true;
    _notification?.close();
    _notification = null;
    _audio.dispose();
  }
}
