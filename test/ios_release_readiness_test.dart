import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS release identity, privacy and platform scope are fixed', () {
    final productionInfo = File('ios/Runner/Info.plist').readAsStringSync();
    final debugInfo = File('ios/Runner/Info-Debug.plist').readAsStringSync();
    final privacy = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(productionInfo, contains('<string>Koya Stores</string>'));
    expect(productionInfo, contains('ITSAppUsesNonExemptEncryption'));
    expect(productionInfo, contains('UIInterfaceOrientationPortrait'));
    expect(productionInfo, isNot(contains('NSBonjourServices')));
    expect(productionInfo, isNot(contains('NSLocalNetworkUsageDescription')));
    expect(productionInfo, isNot(contains('UIBackgroundModes')));
    expect(debugInfo, contains('NSBonjourServices'));
    expect(debugInfo, contains('NSLocalNetworkUsageDescription'));

    for (final dataType in const [
      'NSPrivacyCollectedDataTypeEmailAddress',
      'NSPrivacyCollectedDataTypeUserID',
      'NSPrivacyCollectedDataTypeName',
      'NSPrivacyCollectedDataTypePhoneNumber',
      'NSPrivacyCollectedDataTypePhysicalAddress',
      'NSPrivacyCollectedDataTypePurchaseHistory',
    ]) {
      expect(privacy, contains(dataType));
    }
    expect(privacy, contains('<key>NSPrivacyTracking</key>'));
    expect(privacy, contains('<false/>'));
    expect(privacy, isNot(contains('<string>Email address</string>')));

    expect(project, contains('com.koyas.koyasSupermarket'));
    expect(project, contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0'));
    expect(project, contains('TARGETED_DEVICE_FAMILY = 1'));
    expect(project, contains('PrivacyInfo.xcprivacy in Resources'));
    expect(project, contains('Runner/Info-Debug.plist'));
    expect(project, contains('Flutter/Profile.xcconfig'));
    expect(project, contains('Validate Release Configuration'));
    expect(project, contains('validate_ios_release.sh'));
  });

  test('iOS uses Swift Package Manager without dormant native SDKs', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final scheme = File(
      'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
    ).readAsStringSync();
    final workspace = File(
      'ios/Runner.xcworkspace/contents.xcworkspacedata',
    ).readAsStringSync();
    final appEnvironment = File(
      'lib/core/config/app_environment.dart',
    ).readAsStringSync();
    final dartSources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(File('ios/Podfile').existsSync(), isFalse);
    expect(File('ios/Podfile.lock').existsSync(), isFalse);
    expect(project, contains('FlutterGeneratedPluginSwiftPackage'));
    expect(scheme, contains('Run Prepare Flutter Framework Script'));
    expect(project, isNot(contains('Pods-')));
    expect(workspace, isNot(contains('Pods.xcodeproj')));
    expect(pubspec, isNot(contains('firebase_core:')));
    expect(pubspec, isNot(contains('firebase_messaging:')));
    expect(pubspec, isNot(contains('razorpay_flutter:')));
    expect(pubspec, isNot(contains('file_picker:')));
    expect(dartSources, isNot(contains('package:firebase_')));
    expect(dartSources, isNot(contains('package:razorpay_flutter')));
    expect(appEnvironment, contains('enablePushNotifications = false'));
    expect(appEnvironment, contains('enableRazorpayPayments = false'));
  });

  test('App Store metadata and 6.9-inch screenshots satisfy limits', () {
    String listing(String name) =>
        File('app_store/listing/en-US/$name.txt').readAsStringSync().trim();

    expect(listing('name').runes.length, lessThanOrEqualTo(30));
    expect(listing('subtitle').runes.length, lessThanOrEqualTo(30));
    expect(listing('promotional_text').runes.length, lessThanOrEqualTo(170));
    expect(listing('description').runes.length, lessThanOrEqualTo(4000));
    expect(listing('whats_new').runes.length, lessThanOrEqualTo(4000));
    expect(utf8.encode(listing('keywords')).length, lessThanOrEqualTo(100));
    for (final urlName in const [
      'support_url',
      'privacy_policy_url',
      'privacy_choices_url',
    ]) {
      expect(listing(urlName), startsWith('https://'));
    }

    final screenshots =
        Directory('app_store/assets/iphone-6.9')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.jpg'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(screenshots, hasLength(6));
    for (final screenshot in screenshots) {
      expect(_jpegDimensions(screenshot), (width: 1320, height: 2868));
    }
  });

  test('support, privacy, deletion and reviewer resources are ready', () {
    final config =
        jsonDecode(File('vercel.json').readAsStringSync())
            as Map<String, dynamic>;
    final rewrites = (config['rewrites'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final reviewAccess = File(
      'app_store/APP_REVIEW_ACCESS.md',
    ).readAsStringSync();
    final verifier = File('tool/verify_ios_release.sh').readAsStringSync();

    for (final route in const ['/privacy', '/delete-account', '/support']) {
      expect(
        rewrites.any(
          (rewrite) =>
              rewrite['source'] == route &&
              rewrite['destination'] == '$route.html',
        ),
        isTrue,
      );
    }
    expect(File('web/privacy.html').existsSync(), isTrue);
    expect(File('web/delete-account.html').existsSync(), isTrue);
    expect(File('web/support.html').existsSync(), isTrue);
    expect(reviewAccess, contains('App Store Connect only'));
    expect(reviewAccess, contains('ordinary Supabase Auth customer'));
    expect(verifier, contains('PrivacyInfo.xcprivacy'));
    expect(verifier, contains('ALLOW_UNSIGNED_IOS_VERIFY'));
  });

  test('iOS Release configuration gate rejects incomplete integrations', () {
    if (!Platform.isMacOS) return;

    String encodedDefines(Map<String, String> values) => values.entries
        .map(
          (entry) => base64Encode(utf8.encode('${entry.key}=${entry.value}')),
        )
        .join(',');
    ProcessResult validate(Map<String, String> values) => Process.runSync(
      '/bin/bash',
      const ['tool/validate_ios_release.sh'],
      environment: {
        ...Platform.environment,
        'CONFIGURATION': 'Release',
        'DART_DEFINES': encodedDefines(values),
      },
    );

    final required = <String, String>{
      'SUPABASE_URL': 'https://release-check.supabase.co',
      'SUPABASE_ANON_KEY': 'public-release-validation-key',
      'PRIVACY_POLICY_URL': 'https://release-check.test/privacy',
      'ACCOUNT_DELETION_URL': 'https://release-check.test/delete-account',
      'ENABLE_PLAY_REVIEW_LOGIN': 'true',
    };
    expect(validate(required).exitCode, 0);

    final missing = validate(const {});
    expect(missing.exitCode, isNot(0));
    expect(
      missing.stderr.toString(),
      contains('iOS Release configuration is incomplete'),
    );

    final push = validate({...required, 'ENABLE_PUSH_NOTIFICATIONS': 'true'});
    expect(push.exitCode, isNot(0));
    expect(push.stderr.toString(), contains('Push notifications are excluded'));

    final payment = validate({...required, 'ENABLE_RAZORPAY_PAYMENTS': 'true'});
    expect(payment.exitCode, isNot(0));
    expect(payment.stderr.toString(), contains('payment at handover only'));
  });
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
