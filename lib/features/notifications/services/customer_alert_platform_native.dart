import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'customer_alert_platform.dart';

CustomerAlertPlatform createCustomerAlertPlatform() => NativeCustomerAlerts();

class NativeCustomerAlerts implements CustomerAlertPlatform {
  static Future<void> preparePushChannels() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    for (final sound in [true, false]) {
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          sound
              ? 'customer_order_updates_v1'
              : 'customer_order_updates_silent_v1',
          sound ? 'Order updates' : 'Silent order updates',
          description: 'Pickup and delivery status updates',
          importance: Importance.high,
          playSound: sound,
          enableVibration: sound,
        ),
      );
    }
  }

  static int _nextId = 2100;
  final int _id = _nextId++;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _disposed = false;
  void Function()? _onOpen;
  @override
  Future<bool> enable() async {
    if (_disposed ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return false;
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_order'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (_) {
        if (!_disposed) _onOpen?.call();
      },
    );
    _initialized = true;
    await preparePushChannels();
    if (_disposed) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: false, sound: true) ??
        false;
  }

  @override
  Future<bool> show({
    required String title,
    required String body,
    required bool sound,
    required void Function() onOpen,
  }) async {
    if (!_initialized || _disposed) return false;
    _onOpen = onOpen;
    try {
      await _plugin.show(
        id: _id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            sound
                ? 'customer_order_updates_v1'
                : 'customer_order_updates_silent_v1',
            sound ? 'Order updates' : 'Silent order updates',
            channelDescription: 'Pickup and delivery status updates',
            importance: Importance.high,
            priority: Priority.high,
            playSound: sound,
            enableVibration: sound,
            visibility: NotificationVisibility.private,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentSound: sound,
            presentBadge: false,
          ),
        ),
      );
      if (_disposed) await _plugin.cancel(id: _id);
      return !_disposed;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _onOpen = null;
    if (_initialized) {
      unawaited(_plugin.cancel(id: _id).catchError((Object _) {}));
    }
  }
}
