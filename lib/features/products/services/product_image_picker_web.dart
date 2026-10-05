import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../models/product_image_upload.dart';
import '../../../core/config/usage_policy.dart';

Future<ProductImageUpload?> pickProductImage() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.jpg,.jpeg,.png,.webp,image/jpeg,image/png,image/webp';
  final selection = Completer<web.File?>();

  input.addEventListener(
    'change',
    ((web.Event _) {
      if (!selection.isCompleted) {
        selection.complete(input.files?.item(0));
      }
    }).toJS,
    web.AddEventListenerOptions(once: true),
  );
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      if (!selection.isCompleted) selection.complete(null);
    }).toJS,
    web.AddEventListenerOptions(once: true),
  );
  input.click();

  final file = await selection.future;
  if (file == null) return null;
  return optimiseProductImage(file);
}

Future<ProductImageUpload> optimiseProductImage(web.File file) async {
  if (file.size > ProductImageUpload.maxBytes) {
    throw const FormatException('Choose an image smaller than 5 MB.');
  }
  final buffer = await file.arrayBuffer().toDart;
  ProductImageUpload.fromBytes(
    bytes: buffer.toDart.asUint8List(),
    fileName: file.name,
  );
  final url = web.URL.createObjectURL(file);
  try {
    final image = web.HTMLImageElement()..src = url;
    await image.decode().toDart;
    final width = image.naturalWidth, height = image.naturalHeight;
    if (width <= 0 || height <= 0 || width * height > 32000000) {
      throw const FormatException('Choose a photo smaller than 32 megapixels.');
    }
    for (final edge in [960, 720, 512]) {
      final scale = min(1.0, edge / max(width, height));
      final canvas = web.HTMLCanvasElement()
        ..width = max(1, (width * scale).round())
        ..height = max(1, (height * scale).round());
      final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      context.drawImage(image, 0, 0, canvas.width, canvas.height);
      for (final quality in [0.82, 0.65]) {
        final encoded = Completer<web.Blob?>();
        canvas.toBlob(
          ((web.Blob? blob) => encoded.complete(blob)).toJS,
          'image/webp',
          quality.toJS,
        );
        final blob = await encoded.future;
        if (blob == null || blob.size > UsagePolicy.optimizedImageMaxBytes) {
          continue;
        }
        final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
        return ProductImageUpload.fromBytes(bytes: bytes, fileName: file.name);
      }
    }
    throw const FormatException(
      'This photo could not be reduced to 150 KB. Choose a simpler product photo.',
    );
  } finally {
    web.URL.revokeObjectURL(url);
  }
}
