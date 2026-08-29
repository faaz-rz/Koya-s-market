import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../models/product_image_upload.dart';

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
  input.click();

  final file = await selection.future;
  if (file == null) return null;
  final buffer = await file.arrayBuffer().toDart;
  return ProductImageUpload.fromBytes(
    bytes: buffer.toDart.asUint8List(),
    fileName: file.name,
  );
}
