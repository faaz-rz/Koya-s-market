import 'order_alert_types.dart';

OrderAlertPlatform createOrderAlertPlatform() => _InAppAlerts();

class _InAppAlerts implements OrderAlertPlatform {
  @override
  Future<OrderAlertPermission> enable() async => const OrderAlertPermission(
    sound: false,
    notifications: BrowserAlertPermission.unavailable,
  );
  @override
  Future<bool> playChime() async => false;
  @override
  bool notify({required int count, required void Function() onOpen}) => false;
  @override
  void badge(int count) {}
  @override
  void dismiss() {}
  @override
  void dispose() {}
}
