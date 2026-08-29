import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const destination = 'play_store/assets/phone';
  const names = <String, String>{
    'screenshot-01-home': 'screenshot-01-home',
    'screenshot-02-categories': 'screenshot-02-categories',
    'screenshot-03-product': 'screenshot-03-product',
    'screenshot-04-offer-cart': 'screenshot-04-offer-cart',
    'screenshot-05-delivery': 'screenshot-05-fulfilment',
    'screenshot-06-profile-privacy': 'screenshot-06-profile-privacy',
  };

  await Directory(destination).create(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, image, [args]) async {
      final outputName = names[name];
      if (outputName == null) return false;
      await File(
        '$destination/$outputName.png',
      ).writeAsBytes(image, flush: true);
      return true;
    },
  );
}
