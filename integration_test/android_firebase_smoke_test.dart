import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:koyas_supermarket/core/config/push_configuration.dart';
import 'package:koyas_supermarket/features/notifications/services/push_gateway.dart';

// Run on Android with both production config files. This explicit QA test
// generates only an emulator FCM token without displaying a notification;
// it creates no Supabase account, order or device registration and sends no mail.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('configured Android SDK validates and revokes an FCM token', (
    tester,
  ) async {
    expect(Platform.isAndroid, isTrue);
    expect(PushConfiguration.available, isTrue);
    await FirebasePushGateway.initialize();
    final gateway = FirebasePushGateway();
    expect(gateway.available, isTrue);
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final tokenFile = File('${directory.path}/qa-fcm-token');
    final finished = File('${directory.path}/qa-fcm-validation-done');
    if (await finished.exists()) await finished.delete();
    try {
      final token = await gateway.token();
      expect(token, isNotNull);
      expect(token!.length, greaterThan(50));
      // Private QA transport for a server-side validate_only request. It is
      // removed after validation and never printed or committed to Git.
      await tokenFile.writeAsString(token);
      for (
        var attempt = 0;
        attempt < 60 && !await finished.exists();
        attempt++
      ) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      expect(
        await finished.exists(),
        isTrue,
        reason: 'Provider validation was not completed.',
      );
    } finally {
      await gateway.deleteToken();
      if (await tokenFile.exists()) await tokenFile.delete();
      if (await finished.exists()) await finished.delete();
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
