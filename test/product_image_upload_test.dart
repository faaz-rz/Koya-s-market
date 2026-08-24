import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/products/models/product_image_upload.dart';

void main() {
  test(
    'accepts supported product image bytes and derives trusted MIME type',
    () {
      final image = ProductImageUpload.fromBytes(
        bytes: Uint8List.fromList([
          0x89,
          0x50,
          0x4e,
          0x47,
          0x0d,
          0x0a,
          0x1a,
          0x0a,
          0x00,
        ]),
        fileName: 'new-product.png',
      );

      expect(image.extension, 'png');
      expect(image.contentType, 'image/png');
    },
  );

  test('rejects renamed non-image files', () {
    expect(
      () => ProductImageUpload.fromBytes(
        bytes: Uint8List.fromList('not really an image'.codeUnits),
        fileName: 'unsafe.png',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('valid JPEG, PNG, or WebP'),
        ),
      ),
    );
  });

  test('rejects product images larger than the bucket limit', () {
    expect(
      () => ProductImageUpload.fromBytes(
        bytes: Uint8List(ProductImageUpload.maxBytes + 1),
        fileName: 'too-large.jpg',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('smaller than 5 MB'),
        ),
      ),
    );
  });
}
