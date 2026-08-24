import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/app_environment.dart';
import '../data/notification_repository.dart';

class PushNotificationService {
  PushNotificationService._();

  static final instance = PushNotificationService._();

  StreamSubscription<String>? _refreshSubscription;
  String? _registeredToken;

  Future<void> registerForCurrentUser() async {
    if (!AppEnvironment.enablePushNotifications ||
        !AppEnvironment.hasSupabaseConfig ||
        (!kIsWeb &&
            defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: defaultTargetPlatform == TargetPlatform.iOS,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;
    final token = await messaging.getToken();
    if (token != null) await _register(token);
    await _refreshSubscription?.cancel();
    _refreshSubscription = messaging.onTokenRefresh.listen(_register);
  }

  Future<void> _register(String token) async {
    _registeredToken = token;
    await NotificationRepository().registerDeviceToken(
      token: token,
      platform: kIsWeb
          ? 'web'
          : switch (defaultTargetPlatform) {
              TargetPlatform.iOS => 'ios',
              TargetPlatform.android => 'android',
              _ => 'desktop',
            },
    );
  }

  Future<void> unregister() async {
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    final token = _registeredToken;
    if (token != null && AppEnvironment.hasSupabaseConfig) {
      await NotificationRepository().unregisterDeviceToken(token);
    }
    _registeredToken = null;
  }
}
