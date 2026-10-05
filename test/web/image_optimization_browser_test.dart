@TestOn('browser')
library;

// Run explicitly with flutter test --platform chrome.

import 'dart:async';
import 'dart:js_interop';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:koyas_supermarket/core/config/usage_policy.dart';
import 'package:koyas_supermarket/features/products/services/product_image_picker_web.dart';

void main() {
  test(
    'browser encodes real images within upload bytes and pixel limits',
    () async {
      for (final dimensions in [(1600, 1200), (300, 900), (80, 80)]) {
        final canvas = web.HTMLCanvasElement()
          ..width = dimensions.$1
          ..height = dimensions.$2;
        final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
        context.fillStyle = '#ffffff'.toJS;
        context.fillRect(0, 0, canvas.width, canvas.height);
        for (var i = 0; i < canvas.width; i += 20) {
          context.fillStyle = (i % 40 == 0 ? '#548328' : '#d77b30').toJS;
          context.fillRect(i, 10, 10, canvas.height - 20);
        }
        final encoded = Completer<web.Blob?>();
        canvas.toBlob(((web.Blob? b) => encoded.complete(b)).toJS, 'image/png');
        final file = web.File([(await encoded.future)!].toJS, 'product.png');
        final upload = await optimiseProductImage(file);
        expect(
          upload.bytes.length,
          lessThanOrEqualTo(UsagePolicy.optimizedImageMaxBytes),
        );
        expect(upload.contentType, 'image/webp');
        final url = web.URL.createObjectURL(web.Blob([upload.bytes.toJS].toJS));
        try {
          final image = web.HTMLImageElement()..src = url;
          await image.decode().toDart;
          expect(image.naturalWidth, lessThanOrEqualTo(960));
          expect(image.naturalHeight, lessThanOrEqualTo(960));
          expect(image.naturalWidth, lessThanOrEqualTo(dimensions.$1));
          expect(image.naturalHeight, lessThanOrEqualTo(dimensions.$2));
        } finally {
          web.URL.revokeObjectURL(url);
        }
      }
    },
  );
  test(
    'invalid and oversized uploads are refused before image decode',
    () async {
      final invalid = web.File(['not an image'.toJS].toJS, 'fake.jpg');
      await expectLater(optimiseProductImage(invalid), throwsFormatException);
      final large = web.File(
        [('x' * (5 * 1024 * 1024 + 1)).toJS].toJS,
        'large.png',
      );
      await expectLater(optimiseProductImage(large), throwsFormatException);
    },
  );
}
