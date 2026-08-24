import 'models/product.dart';

/// Groups catalogue SKUs that differ only by a clearly stated pack quantity.
///
/// The grouping is deliberately conservative: a product must contain an
/// explicit mass or volume in its customer-facing name. This prevents similar
/// flavours, formulas, or vague billing-only packs from being merged.
class ProductFamily {
  const ProductFamily({
    required this.key,
    required this.name,
    required this.variants,
    required this.representative,
  });

  final String key;
  final String name;
  final List<Product> variants;
  final Product representative;

  bool get hasMultipleSizes => variants.length > 1;
  bool get isAvailable => variants.any((product) => product.isAvailable);
  int get lowestPricePaise => variants
      .map((product) => product.effectivePricePaise)
      .reduce((left, right) => left < right ? left : right);

  List<String> get sizeLabels => variants
      .map(ProductVariants.variantLabel)
      .whereType<String>()
      .toList(growable: false);

  int cartQuantity(Map<String, int> quantities) => variants.fold(
    0,
    (total, product) => total + (quantities[product.id] ?? 0),
  );

  bool isFavorite(Set<String> favoriteIds) =>
      variants.any((product) => favoriteIds.contains(product.id));
}

abstract final class ProductVariants {
  static final RegExp _quantityPattern = RegExp(
    r'\b(\d+(?:\.\d+)?)\s*(kg|kgs|kilograms?|g|gm|gms|grams?|ml|millilit(?:er|re)s?|l|ltr|lit(?:er|re)s?)\b',
    caseSensitive: false,
  );
  static final RegExp _pricePackPattern = RegExp(
    r'\s*\([^)]*₹[^)]*\)',
    caseSensitive: false,
  );
  static final RegExp _generatedVariantPattern = RegExp(
    r'\s*·\s*Variant\s*\d+\b',
    caseSensitive: false,
  );

  static String? variantLabel(Product product) =>
      _sizeFromName(product.name)?.label;

  static String familyName(Product product) {
    final withoutBillingSuffix = product.name
        .replaceAll(_pricePackPattern, '')
        .replaceAll(_generatedVariantPattern, '');
    final withoutQuantity = withoutBillingSuffix.replaceAll(
      _quantityPattern,
      '',
    );
    return withoutQuantity
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s+([),.])'), r'$1')
        .trim();
  }

  static ProductFamily familyFor({
    required Product product,
    required Iterable<Product> catalogue,
  }) {
    return _index(catalogue)[product.id] ?? _single(product);
  }

  /// Returns one storefront family for each matched/search-visible product.
  /// Family variants are taken from the full catalogue so a search hit for one
  /// size still opens every available size of that exact product.
  static List<ProductFamily> collapse({
    required Iterable<Product> visibleProducts,
    required Iterable<Product> catalogue,
  }) {
    final index = _index(catalogue);
    final seen = <String>{};
    final families = <ProductFamily>[];
    for (final product in visibleProducts) {
      final family = index[product.id] ?? _single(product);
      if (seen.add(family.key)) families.add(family);
    }
    return families;
  }

  static Map<String, ProductFamily> _index(Iterable<Product> catalogue) {
    final products = catalogue.toList(growable: false);
    final sizedBuckets = <String, List<Product>>{};
    final result = <String, ProductFamily>{};

    for (final product in products) {
      final size = _sizeFromName(product.name);
      if (size == null) {
        result[product.id] = _single(product);
        continue;
      }
      final key = _candidateKey(product);
      sizedBuckets.putIfAbsent(key, () => <Product>[]).add(product);
    }

    for (final entry in sizedBuckets.entries) {
      final candidates = entry.value;
      if (candidates.length == 1) {
        final product = candidates.single;
        result[product.id] = _single(product);
        continue;
      }

      // Old/new barcodes can repeat the same size. Keep the best active SKU so
      // customers do not see duplicate 500 g choices.
      final preferredBySize = <String, Product>{};
      for (final candidate in candidates) {
        final sizeKey = _sizeFromName(candidate.name)!.key;
        final current = preferredBySize[sizeKey];
        if (current == null || _isPreferred(candidate, current)) {
          preferredBySize[sizeKey] = candidate;
        }
      }

      final variants = preferredBySize.values.toList(growable: false)
        ..sort(_compareBySize);
      final representative = _representative(variants);
      final family = ProductFamily(
        key: 'family:${entry.key}',
        name: familyName(representative),
        variants: variants,
        representative: representative,
      );
      for (final candidate in candidates) {
        result[candidate.id] = family;
      }
    }
    return result;
  }

  static ProductFamily _single(Product product) => ProductFamily(
    key: 'product:${product.id}',
    name: product.name,
    variants: <Product>[product],
    representative: product,
  );

  static String _candidateKey(Product product) => [
    product.categoryId,
    _normalize(product.brand),
    _normalize(familyName(product)),
  ].join('|');

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _isPreferred(Product candidate, Product current) {
    if (candidate.isAvailable != current.isAvailable) {
      return candidate.isAvailable;
    }
    if (candidate.featured != current.featured) return candidate.featured;
    if (candidate.imageAsset.isNotEmpty != current.imageAsset.isNotEmpty) {
      return candidate.imageAsset.isNotEmpty;
    }
    return candidate.effectivePricePaise < current.effectivePricePaise;
  }

  static Product _representative(List<Product> variants) {
    for (final product in variants) {
      if (product.isAvailable) return product;
    }
    for (final product in variants) {
      if (product.imageAsset.isNotEmpty) return product;
    }
    return variants.first;
  }

  static int _compareBySize(Product left, Product right) {
    final leftSize = _sizeFromName(left.name)!;
    final rightSize = _sizeFromName(right.name)!;
    final dimensionOrder = leftSize.dimension.compareTo(rightSize.dimension);
    if (dimensionOrder != 0) return dimensionOrder;
    final amountOrder = leftSize.baseAmount.compareTo(rightSize.baseAmount);
    if (amountOrder != 0) return amountOrder;
    return left.effectivePricePaise.compareTo(right.effectivePricePaise);
  }

  static _ProductSize? _sizeFromName(String name) {
    final match = _quantityPattern.firstMatch(name);
    if (match == null) return null;
    final amount = double.parse(match.group(1)!);
    final rawUnit = match.group(2)!.toLowerCase();
    final isMass =
        rawUnit.startsWith('g') ||
        rawUnit.startsWith('kg') ||
        rawUnit.startsWith('kilogram');
    final isLargeUnit =
        rawUnit.startsWith('kg') ||
        rawUnit.startsWith('kilogram') ||
        rawUnit == 'l' ||
        rawUnit.startsWith('ltr') ||
        rawUnit.startsWith('lit');
    final unit = isMass
        ? (isLargeUnit ? 'kg' : 'g')
        : (isLargeUnit ? 'L' : 'ml');
    final baseAmount = isLargeUnit ? amount * 1000 : amount;
    final displayAmount = amount == amount.roundToDouble()
        ? amount.toInt().toString()
        : amount.toString().replaceFirst(RegExp(r'0+$'), '');
    return _ProductSize(
      label: '$displayAmount $unit',
      key: '${isMass ? 'mass' : 'volume'}:${baseAmount.toStringAsFixed(3)}',
      dimension: isMass ? 0 : 1,
      baseAmount: baseAmount,
    );
  }
}

class _ProductSize {
  const _ProductSize({
    required this.label,
    required this.key,
    required this.dimension,
    required this.baseAmount,
  });

  final String label;
  final String key;
  final int dimension;
  final double baseAmount;
}
