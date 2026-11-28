import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final releaseVersion = RegExp(
    r'^version:[ \t]+([^\s+]+)\+([1-9][0-9]*)[ \t]*$',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync());

  test(
    'Android release identity, permission, API and safety gates are fixed',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final rootGradle = File('android/build.gradle.kts').readAsStringSync();
      final settings = File('android/settings.gradle.kts').readAsStringSync();
      final gradleProperties = File(
        'android/gradle.properties',
      ).readAsStringSync();
      final wrapper = File(
        'android/gradle/wrapper/gradle-wrapper.properties',
      ).readAsStringSync();

      expect(
        manifest,
        contains(
          '<uses-permission android:name="android.permission.INTERNET"/>',
        ),
      );
      expect(manifest, contains('android:label="Koya Stores"'));
      expect(gradle, contains('applicationId = "com.koyas.koyas_supermarket"'));
      expect(gradle, contains('compileSdk = 37'));
      expect(gradle, contains('targetSdk = 36'));
      expect(settings, contains('version "9.3.2"'));
      expect(
        settings,
        contains(
          'id("org.jetbrains.kotlin.android") version "2.3.21" apply false',
        ),
      );
      expect(gradle, isNot(contains('id("kotlin-android")')));
      expect(gradleProperties, contains('android.builtInKotlin=true'));
      expect(wrapper, contains('gradle-9.5.0-all.zip'));
      expect(gradle, contains('Release signing is required'));
      expect(gradle, contains('Release legal URLs are required'));
      expect(
        rootGradle,
        contains('"androidx.test:runner:1.2+" -> useVersion("1.2.0")'),
      );
      expect(
        rootGradle,
        contains('"androidx.test:rules:1.2+" -> useVersion("1.2.0")'),
      );
      expect(
        rootGradle,
        contains(
          '"androidx.test.espresso:espresso-core:3.3+" -> useVersion("3.3.0")',
        ),
      );
      expect(
        releaseVersion,
        isNotNull,
        reason: 'Set version and build number in pubspec.yaml',
      );
    },
  );

  test('public privacy and account-deletion resources are routable', () {
    final privacy = File('web/privacy.html').readAsStringSync();
    final deletion = File('web/delete-account.html').readAsStringSync();
    final config =
        jsonDecode(File('vercel.json').readAsStringSync())
            as Map<String, dynamic>;
    final rewrites = (config['rewrites'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final buildScript = File('tool/build_admin_web.sh').readAsStringSync();

    expect(privacy, contains('<meta name="robots" content="index,follow"'));
    expect(privacy, contains('Information we collect'));
    expect(privacy, contains('Supabase'));
    expect(privacy, contains('does not include third-party advertising'));
    expect(privacy, isNot(contains('Firebase may process')));
    expect(privacy, isNot(contains('Razorpay processes')));
    expect(privacy, contains('/delete-account'));
    expect(deletion, contains('Delete your account'));
    expect(deletion, contains('Request deletion without app access'));
    expect(deletion, contains('What is deleted'));
    expect(config['buildCommand'], 'bash tool/build_admin_web.sh');
    expect(config['outputDirectory'], 'build/web');
    expect(
      File('.flutter-version').readAsStringSync().trim(),
      matches(r'^\d+\.\d+\.\d+$'),
    );
    expect(buildScript, contains('.flutter-version'));
    expect(
      File('.github/workflows/security.yml').readAsStringSync(),
      contains('cat .flutter-version'),
    );
    expect(buildScript, contains('sb_secret_*|*service_role*'));
    expect(buildScript, contains('-t lib/admin_main.dart'));
    expect(
      rewrites.any(
        (rewrite) =>
            rewrite['source'] == '/privacy' &&
            rewrite['destination'] == '/privacy.html',
      ),
      isTrue,
    );
    expect(
      rewrites.any(
        (rewrite) =>
            rewrite['source'] == '/delete-account' &&
            rewrite['destination'] == '/delete-account.html',
      ),
      isTrue,
    );
  });

  test('Play listing contains six current 1080 by 1920 phone screenshots', () {
    final screenshots =
        Directory('play_store/assets/phone')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('-1080x1920.jpg'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    expect(screenshots, hasLength(6));
    for (final screenshot in screenshots) {
      expect(_jpegDimensions(screenshot), (width: 1080, height: 1920));
      expect(screenshot.lengthSync(), lessThanOrEqualTo(8 * 1024 * 1024));
    }
  });

  test('Play icon, feature graphic and listing copy meet upload limits', () {
    final icon = File('play_store/assets/app-icon-512.png');
    expect(_pngHeader(icon), (width: 512, height: 512, depth: 8, colorType: 6));
    expect(icon.lengthSync(), lessThanOrEqualTo(1024 * 1024));
    final graphic = File('play_store/assets/feature-graphic-1024x500.png');
    expect(_pngHeader(graphic), (
      width: 1024,
      height: 500,
      depth: 8,
      colorType: 2,
    ));

    expect(
      releaseVersion,
      isNotNull,
      reason: 'Set version and build number in pubspec.yaml',
    );
    final limits = {
      'title.txt': 30,
      'short_description.txt': 80,
      'full_description.txt': 4000,
      'release_notes_${releaseVersion!.group(1)}.txt': 500,
    };
    for (final entry in limits.entries) {
      final copy = File(
        'play_store/listing/en-US/${entry.key}',
      ).readAsStringSync().trim();
      expect(
        copy.runes.length,
        inInclusiveRange(1, entry.value),
        reason: entry.key,
      );
    }
  });

  test('account deletion is authenticated, atomic and privacy preserving', () {
    final migration = File(
      'supabase/migrations/202608280003_account_deletion.sql',
    ).readAsStringSync();
    final function = File(
      'supabase/functions/delete-account/index.ts',
    ).readAsStringSync();
    final config = File('supabase/config.toml').readAsStringSync();
    final handler = File(
      'supabase/functions/delete-account/handler.ts',
    ).readAsStringSync();
    final dialog = File(
      'lib/features/profile/widgets/delete_account_dialog.dart',
    ).readAsStringSync();
    final profile = File(
      'lib/features/profile/screens/profile_screen.dart',
    ).readAsStringSync();
    final clientSources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(migration, contains('references auth.users(id) on delete set null'));
    expect(migration, contains('before delete on auth.users'));
    expect(migration, contains("order_status not in ('collected'"));
    expect(migration, contains("customer_name_snapshot = 'Deleted customer'"));
    expect(migration, contains('delivery_recipient_phone_snapshot = null'));
    expect(migration, contains('revoke all on function'));
    expect(function, contains('userClient.auth.getUser()'));
    expect(handler, contains('payload.confirmation !== "DELETE_WITH_OTP"'));
    expect(handler, contains('deps.verifyCode(user.email, payload.otp)'));
    expect(handler, contains('deps.consume(user, payload.challenge_id)'));
    expect(function, contains('adminClient.auth.admin.deleteUser'));
    expect(function, contains('SUPABASE_SERVICE_ROLE_KEY'));
    expect(clientSources, isNot(contains('SUPABASE_SERVICE_ROLE_KEY')));
    expect(config, contains('[functions.delete-account]\nverify_jwt = true'));
    expect(profile, contains("Key('profile-privacy-policy')"));
    expect(profile, contains("Key('profile-delete-account')"));
    expect(dialog, contains("Key('delete-account-confirmation')"));
    expect(dialog, contains("Key('delete-account-final')"));
    expect(dialog, contains("Key('delete-account-otp')"));
  });

  test('customer and staff sign-in screens expose email codes only', () {
    final customer = File(
      'lib/features/auth/screens/login_screen.dart',
    ).readAsStringSync();
    final staff = File(
      'lib/admin/screens/admin_login_screen.dart',
    ).readAsStringSync();

    expect(customer, contains("Key('login-otp')"));
    expect(customer, contains("Key('login-privacy-policy')"));
    expect(staff, contains("Key('admin-otp')"));
    for (final screen in [customer, staff]) {
      expect(screen, contains('verifyEmailOtp'));
      expect(screen, isNot(contains('signInWithPassword')));
      expect(screen, isNot(contains('SetPasswordDialog')));
      expect(screen, isNot(contains('App review access')));
    }
  });
}

({int width, int height, int depth, int colorType}) _pngHeader(File file) {
  final bytes = file.readAsBytesSync();
  if (bytes.length < 26 ||
      base64Encode(bytes.sublist(0, 8)) != 'iVBORw0KGgo=' ||
      ascii.decode(bytes.sublist(12, 16)) != 'IHDR') {
    throw FormatException('Not a PNG: ${file.path}');
  }
  final header = bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length);
  return (
    width: header.getUint32(16),
    height: header.getUint32(20),
    depth: header.getUint8(24),
    colorType: header.getUint8(25),
  );
}

({int width, int height}) _jpegDimensions(File file) {
  final bytes = file.readAsBytesSync();
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) {
    throw FormatException('Not a JPEG: ${file.path}');
  }

  var offset = 2;
  while (offset + 8 < bytes.length) {
    if (bytes[offset] != 0xff) {
      offset++;
      continue;
    }
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) break;
    final marker = bytes[offset++];
    if (marker == 0xd8 || marker == 0xd9) continue;
    if (marker == 0xda) break;
    if (offset + 1 >= bytes.length) break;
    final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
    if (segmentLength < 2 || offset + segmentLength > bytes.length) break;
    const startOfFrameMarkers = {
      0xc0,
      0xc1,
      0xc2,
      0xc3,
      0xc5,
      0xc6,
      0xc7,
      0xc9,
      0xca,
      0xcb,
      0xcd,
      0xce,
      0xcf,
    };
    if (startOfFrameMarkers.contains(marker)) {
      final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      return (width: width, height: height);
    }
    offset += segmentLength;
  }
  throw FormatException('JPEG dimensions not found: ${file.path}');
}
