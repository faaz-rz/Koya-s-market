import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:koyas_supermarket/features/admin/notifications/order_alert_platform.dart';

void main() {
  final platform = createOrderAlertPlatform();
  final output = web.document.getElementById('result')!;
  web.document.getElementById('enable')!.onClick.listen((_) async {
    final result = await platform.enable();
    output.textContent = jsonEncode({
      'sound': result.sound,
      'permission': result.notifications.name,
    });
  });
  web.document.getElementById('notify')!.onClick.listen((_) async {
    final played = await platform.playChime();
    final shown = platform.notify(
      count: 1,
      onOpen: () => output.textContent = 'opened',
    );
    platform.badge(1);
    output.textContent = jsonEncode({'played': played, 'shown': shown});
  });
  web.document.getElementById('clear')!.onClick.listen((_) {
    platform.dispose();
    output.textContent = 'cleared';
  });
}
