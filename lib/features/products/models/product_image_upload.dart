import 'dart:typed_data';

class ProductImageUpload {
  const ProductImageUpload._({
    required this.bytes,
    required this.fileName,
    required this.extension,
    required this.contentType,
  });

  static const maxBytes = 5 * 1024 * 1024;

  final Uint8List bytes;
  final String fileName;
  final String extension;
  final String contentType;

  factory ProductImageUpload.fromBytes({
    required Uint8List bytes,
    required String fileName,
  }) {
    if (bytes.isEmpty) {
      throw const FormatException('The selected image is empty.');
    }
    if (bytes.length > maxBytes) {
      throw const FormatException('Choose an image smaller than 5 MB.');
    }

    final detected = _detectImageType(bytes);
    if (detected == null) {
      throw const FormatException('Choose a valid JPEG, PNG, or WebP image.');
    }

    return ProductImageUpload._(
      bytes: bytes,
      fileName: fileName,
      extension: detected.$1,
      contentType: detected.$2,
    );
  }

  static (String, String)? _detectImageType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return ('jpg', 'image/jpeg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return ('png', 'image/png');
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return ('webp', 'image/webp');
    }
    return null;
  }
}
