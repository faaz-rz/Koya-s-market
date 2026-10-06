import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

abstract final class PushConfiguration {
  static const enabled = bool.fromEnvironment('ENABLE_PUSH_NOTIFICATIONS');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const androidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  );
  static const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static bool get available =>
      enabled &&
      !kIsWeb &&
      projectId.isNotEmpty &&
      senderId.isNotEmpty &&
      (defaultTargetPlatform == TargetPlatform.android &&
              androidApiKey.isNotEmpty &&
              androidAppId.isNotEmpty ||
          defaultTargetPlatform == TargetPlatform.iOS &&
              iosApiKey.isNotEmpty &&
              iosAppId.isNotEmpty);
  static FirebaseOptions get options => FirebaseOptions(
    apiKey: defaultTargetPlatform == TargetPlatform.iOS
        ? iosApiKey
        : androidApiKey,
    appId: defaultTargetPlatform == TargetPlatform.iOS
        ? iosAppId
        : androidAppId,
    messagingSenderId: senderId,
    projectId: projectId,
    iosBundleId: defaultTargetPlatform == TargetPlatform.iOS
        ? 'com.koyas.koyasSupermarket'
        : null,
  );
}
