import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/push_configuration.dart';
import 'customer_alert_platform_native.dart';

@pragma('vm:entry-point')
Future<void> orderPushBackgroundHandler(RemoteMessage message) async {
  // The visible notification payload is displayed by Android/APNs. No customer
  // state, navigation, tokens, or background location are accessed here.
}

abstract class PushGateway {
  bool get available;
  Future<bool> permission({bool request = false});
  Future<String?> token();
  Future<void> deleteToken();
  Stream<String> get tokenChanges;
  Stream<Map<String, dynamic>> get opened;
  Stream<Map<String, dynamic>> get received;
  Future<Map<String, dynamic>?> initialMessage();
}

final pushGatewayProvider = Provider<PushGateway>(
  (ref) => FirebasePushGateway(),
);

class FirebasePushGateway implements PushGateway {
  static bool _initialized = false;
  @override
  bool get available => PushConfiguration.available && _initialized;
  static Future<void> initialize() async {
    if (!PushConfiguration.available) return;
    try {
      await Firebase.initializeApp(options: PushConfiguration.options);
      FirebaseMessaging.onBackgroundMessage(orderPushBackgroundHandler);
      // Live database updates own foreground presentation, so an FCM copy never
      // causes a second banner/chime while the app is open.
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: false,
            sound: false,
          );
      await NativeCustomerAlerts.preparePushChannels();
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  @override
  Future<bool> permission({bool request = false}) async {
    final settings = request
        ? await _messaging.requestPermission(
            alert: true,
            sound: true,
            badge: false,
          )
        : await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> token() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // APNs may finish registering just after permission is granted. Bounded
      // waiting avoids calling getToken before APNs is ready.
      for (var i = 0; i < 6; i++) {
        if (await _messaging.getAPNSToken() != null) break;
        if (i == 5) return null;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    await _messaging.setAutoInitEnabled(true);
    return _messaging.getToken();
  }

  @override
  Future<void> deleteToken() async {
    if (!available) return;
    await _messaging.setAutoInitEnabled(false);
    await _messaging.deleteToken();
  }

  @override
  Stream<String> get tokenChanges => _messaging.onTokenRefresh;
  @override
  Stream<Map<String, dynamic>> get opened =>
      FirebaseMessaging.onMessageOpenedApp.map((m) => m.data);
  @override
  Stream<Map<String, dynamic>> get received =>
      FirebaseMessaging.onMessage.map((m) => m.data);
  @override
  Future<Map<String, dynamic>?> initialMessage() async =>
      (await _messaging.getInitialMessage())?.data;
}
