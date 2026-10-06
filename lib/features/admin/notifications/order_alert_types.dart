enum BrowserAlertPermission { granted, denied, unavailable }

class OrderAlertPermission {
  const OrderAlertPermission({
    required this.sound,
    required this.notifications,
  });
  final bool sound;
  final BrowserAlertPermission notifications;
}

abstract class OrderAlertPlatform {
  Future<OrderAlertPermission> enable();
  Future<bool> playChime();
  bool notify({required int count, required void Function() onOpen});
  void badge(int count);
  void dismiss();
  void dispose();
}
