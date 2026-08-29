import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const destination = 'app_store/assets/iphone-6.9';
  await Directory(destination).create(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, image, [args]) async {
      await File('$destination/$name.png').writeAsBytes(image, flush: true);
      return true;
    },
  );
}
