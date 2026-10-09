import 'models/product.dart';
import '../store/data/generated_product_catalog.dart';

/// Reviewed local photographs, keyed by product identity rather than brand or
/// category. Prices and stock always come from the live catalogue.
abstract final class BundledProductImages {
  static final _products = {
    for (final product in GeneratedProductCatalog.products)
      if (product.imageAsset.isNotEmpty) product.id: product,
  };

  static String assetFor(Product product) {
    // A staff upload supersedes the bundled photograph, including when it is
    // removed/replaced. Do not silently hide a failed upload with stale media.
    if (product.imagePath.isNotEmpty || product.imageUrl?.isNotEmpty == true) {
      return '';
    }
    final reviewed = _products[product.id];
    if (reviewed == null ||
        _normalize(reviewed.name) != _normalize(product.name) ||
        _normalize(reviewed.unit) != _normalize(product.unit) ||
        (product.barcode.isNotEmpty && reviewed.barcode != product.barcode)) {
      return '';
    }
    return reviewed.imageAsset;
  }

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
