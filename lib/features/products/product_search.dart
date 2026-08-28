import 'models/product.dart';

enum ProductSearchSuggestionKind { product, brand, category }

class ProductSearchSuggestion {
  const ProductSearchSuggestion({
    required this.kind,
    required this.label,
    required this.query,
    required this.detail,
    this.product,
  });

  final ProductSearchSuggestionKind kind;
  final String label;
  final String query;
  final String detail;
  final Product? product;
}

/// Local, relevance-ranked catalogue search for the customer and admin apps.
///
/// Product data stays on-device, while semantic tags make intent searches such
/// as "washing" behave like grocery-app search without requiring a paid search
/// service.
abstract final class ProductSearch {
  static final _catalogueIndexes = Expando<_CatalogueSearchIndex>(
    'product-search-index',
  );

  static const _stopWords = <String>{
    'a',
    'an',
    'and',
    'for',
    'in',
    'me',
    'of',
    'please',
    'show',
    'the',
    'to',
    'want',
    'buy',
    'need',
    'with',
  };

  static const _tokenAliases = <String, String>{
    'agarbathi': 'agarbatti',
    'aata': 'atta',
    'biskit': 'biscuit',
    'biskut': 'biscuit',
    'biscuits': 'biscuit',
    'biscot': 'biscuit',
    'biscots': 'biscuit',
    'biscut': 'biscuit',
    'biscuts': 'biscuit',
    'cookies': 'biscuit',
    'chai': 'tea',
    'chawal': 'rice',
    'cheeni': 'sugar',
    'coldrink': 'drink',
    'coldrinks': 'drink',
    'daal': 'dal',
    'dall': 'dal',
    'detergents': 'detergent',
    'dishes': 'dish',
    'doodh': 'milk',
    'groceries': 'grocery',
    'lotions': 'lotion',
    'masale': 'masala',
    'masalas': 'masala',
    'namkeen': 'snack',
    'powders': 'powder',
    'shampoos': 'shampoo',
    'soaps': 'soap',
    'saboon': 'soap',
    'sabun': 'soap',
    'sweets': 'sweet',
    'tel': 'oil',
    'utensils': 'utensil',
    'washed': 'wash',
    'washer': 'wash',
    'washes': 'wash',
  };

  static List<Product> search({
    required Iterable<Product> products,
    required String query,
    String? categoryId,
    bool Function(Product product)? filter,
  }) {
    final index = _indexFor(products);
    bool included(_SearchDocument document) =>
        (categoryId == null || document.product.categoryId == categoryId) &&
        (filter == null || filter(document.product));
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return index.documents
          .where(included)
          .map((document) => document.product)
          .toList(growable: false);
    }

    final queryTokens = _tokens(
      normalizedQuery,
    ).where((token) => !_stopWords.contains(token)).toSet();
    if (queryTokens.isEmpty) {
      return index.documents
          .where(included)
          .map((document) => document.product)
          .toList(growable: false);
    }

    final ranked = <({Product product, int score})>[];
    for (final document in index.documents) {
      if (!included(document)) continue;
      final score = _score(document, normalizedQuery, queryTokens);
      if (score > 0) {
        ranked.add((product: document.product, score: score));
      }
    }
    ranked.sort((left, right) {
      final scoreOrder = right.score.compareTo(left.score);
      if (scoreOrder != 0) return scoreOrder;
      final stockOrder = right.product.isAvailable ? 1 : 0;
      final leftStockOrder = left.product.isAvailable ? 1 : 0;
      if (stockOrder != leftStockOrder) return stockOrder - leftStockOrder;
      if (left.product.featured != right.product.featured) {
        return right.product.featured ? 1 : -1;
      }
      return left.product.name.compareTo(right.product.name);
    });
    return ranked.map((result) => result.product).toList(growable: false);
  }

  /// Builds compact type-ahead suggestions from the same ranked catalogue
  /// results used by [search]. This keeps suggestions and the product grid in
  /// sync and does not require a remote search service.
  static List<ProductSearchSuggestion> suggestions({
    required Iterable<Product> products,
    required String query,
    String? categoryId,
    bool Function(Product product)? filter,
    int limit = 8,
  }) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.length < 2 || limit <= 0) return const [];

    final ranked = search(
      products: products,
      query: query,
      categoryId: categoryId,
      filter: filter,
    );
    if (ranked.isEmpty) return const [];

    final suggestions = <ProductSearchSuggestion>[];
    final seen = <String>{};
    final productSuggestionsPerBrand = <String, int>{};

    void add(ProductSearchSuggestion suggestion) {
      if (suggestions.length >= limit) return;
      final key = '${suggestion.kind.name}:${_normalize(suggestion.query)}';
      if (seen.add(key)) suggestions.add(suggestion);
    }

    for (final product in ranked.take(limit * 5)) {
      final brand = product.brand.trim();
      if (brand.isNotEmpty && _normalize(brand).contains(normalizedQuery)) {
        add(
          ProductSearchSuggestion(
            kind: ProductSearchSuggestionKind.brand,
            label: brand,
            query: brand,
            detail: 'Brand',
          ),
        );
      }

      final subcategory = product.subcategory.trim();
      if (subcategory.isNotEmpty &&
          _normalize(subcategory).contains(normalizedQuery)) {
        add(
          ProductSearchSuggestion(
            kind: ProductSearchSuggestionKind.category,
            label: subcategory,
            query: subcategory,
            detail: 'Category',
          ),
        );
      }

      final hasProductImage =
          product.imageAsset.isNotEmpty ||
          product.imagePath.isNotEmpty ||
          product.imageUrl?.isNotEmpty == true ||
          product.imageBytes?.isNotEmpty == true;
      final presentableProduct = brand.isNotEmpty || hasProductImage;
      final brandKey = _normalize(brand);
      final brandSuggestionCount = productSuggestionsPerBrand[brandKey] ?? 0;
      if (presentableProduct &&
          (brandKey.isEmpty || brandSuggestionCount < 2)) {
        add(
          ProductSearchSuggestion(
            kind: ProductSearchSuggestionKind.product,
            label: product.name,
            query: product.name,
            detail: [if (brand.isNotEmpty) brand, product.unit].join(' · '),
            product: product,
          ),
        );
        productSuggestionsPerBrand[brandKey] = brandSuggestionCount + 1;
      }
      if (suggestions.length >= limit) break;
    }
    return suggestions;
  }

  static int _score(
    _SearchDocument document,
    String normalizedQuery,
    Set<String> queryTokens,
  ) {
    final product = document.product;
    final name = document.name;
    final brand = document.brand;
    final subcategory = document.subcategory;
    final itemCode = document.itemCode;
    final barcode = document.barcode;

    var score = 0;
    if (name.text == normalizedQuery) score += 1600;
    if (brand.text == normalizedQuery) score += 1100;
    if (name.text.startsWith('$normalizedQuery ')) score += 850;
    if (name.text.contains(normalizedQuery)) score += 650;
    if (brand.text.startsWith(normalizedQuery)) score += 500;
    if (subcategory.text.contains(normalizedQuery)) score += 420;
    if (barcode.text == normalizedQuery || itemCode.text == normalizedQuery) {
      score += 2000;
    }

    final broadLaundryIntent =
        queryTokens.length == 1 &&
        queryTokens.any(
          const {'wash', 'washing', 'laundry', 'clothes'}.contains,
        );
    final clearlyLaundry =
        !document.productText.contains('dishwash') &&
        !document.productText.contains('dish wash') &&
        const [
          'laundry',
          'detergent',
          'fabric conditioner',
          'stain remover',
          'washing powder',
          'washing liquid',
        ].any(document.productText.contains);
    if (broadLaundryIntent && clearlyLaundry) score += 650;

    for (final queryToken in queryTokens) {
      var bestTokenScore = 0;
      for (final field in document.fields) {
        for (final candidateToken in field.tokens) {
          final tokenScore = _tokenScore(
            queryToken,
            candidateToken,
            field.weight,
          );
          if (tokenScore > bestTokenScore) bestTokenScore = tokenScore;
        }
      }
      // Every meaningful word must match. This keeps "washing powder" focused
      // on laundry powder instead of unrelated talcum or food powders.
      if (bestTokenScore == 0) return 0;
      score += bestTokenScore;
    }

    if (product.isAvailable) score += 12;
    if (product.featured) score += 6;
    return score;
  }

  static int _tokenScore(String query, String candidate, int weight) {
    if (query == candidate) return weight;
    if (query.length >= 3 && candidate.startsWith(query)) {
      return (weight * 0.78).round();
    }
    if (candidate.length >= 3 && query.startsWith(candidate)) {
      return (weight * 0.62).round();
    }
    if (query.length < 4 || candidate.length < 4) return 0;
    final allowedDistance = query.length >= 9 ? 2 : 1;
    if ((query.length - candidate.length).abs() > allowedDistance) return 0;
    return _editDistance(query, candidate, limit: allowedDistance) <=
            allowedDistance
        ? (weight * 0.44).round()
        : 0;
  }

  static String _semanticTags(Product product) {
    final source = _normalize(
      '${product.name} ${product.brand} ${product.subcategory} '
      '${product.description}',
    );
    final tags = <String>{};

    void add(String values) => tags.addAll(_tokens(values));
    bool hasAny(Iterable<String> values) => values.any(source.contains);

    if (hasAny(const [
      'laundry',
      'detergent',
      'fabric conditioner',
      'stain remover',
      'washing liquid',
      'washing powder',
    ])) {
      add('wash washing laundry clothes cloth cleaning detergent');
    }
    if (hasAny(const ['detergent bar', 'laundry bar'])) {
      add('washing laundry clothes soap bar');
    }
    if (hasAny(const ['dishwash', 'dish wash', 'dishwashing'])) {
      add('wash washing dish dishes utensil utensils kitchen cleaning');
    }
    if (hasAny(const ['floor cleaner', 'toilet cleaner', 'surface cleaner'])) {
      add('clean cleaning cleaner home house wash');
    }
    if (hasAny(const ['biscuit', 'cookie'])) {
      add('biscuit biscuits cookie cookies snack');
    }
    if (hasAny(const ['atta', 'flour', 'maida', 'besan'])) {
      add('atta flour wheat baking staple grocery');
    }
    if (hasAny(const ['dal', 'dall', 'pulse'])) {
      add('dal dall pulse pulses lentil grocery staple');
    }
    if (hasAny(const ['rice', 'basmati', 'hmt'])) {
      add('rice chawal grocery staple');
    }
    if (hasAny(const ['soft drink', 'cool drink', 'juice', 'squash'])) {
      add('drink drinks beverage cold cool juice');
    }
    if (hasAny(const ['shampoo', 'conditioner', 'hair oil', 'hair colour'])) {
      add('hair shampoo conditioner grooming personal care');
    }
    if (hasAny(const ['toothpaste', 'tooth powder', 'tooth cream'])) {
      add('tooth teeth dental oral care paste');
    }
    if (hasAny(const ['agarbatti', 'incense', 'dhoop', 'pooja'])) {
      add('pooja puja prayer incense agarbatti dhoop festive');
    }
    if (hasAny(const ['baby', 'diaper'])) add('baby child kids care');
    if (hasAny(const ['oil', 'ghee'])) add('oil cooking edible grocery');

    switch (product.visualKey) {
      case 'staples':
        add('grocery groceries staples kirana pantry');
      case 'breakfast':
        add('breakfast ready cook cereal oats');
      case 'snacks':
        add('snack snacks sweets namkeen');
      case 'beverages':
        add('drink drinks beverage beverages');
      case 'dairy':
        add('dairy milk frozen');
      case 'fresh':
        add('fresh fruit fruits vegetable vegetables produce');
      case 'personal':
        add('personal care grooming beauty');
      case 'baby':
        add('baby child kids care');
      case 'household':
        add('home house household cleaning');
      case 'health':
        add('health wellness medicine care');
      case 'pooja':
        add('pooja puja prayer festive');
      case 'general':
        add('household general utility');
    }
    return tags.join(' ');
  }

  static List<String> _tokens(String value) => _normalize(value)
      .split(' ')
      .where((token) => token.isNotEmpty)
      .map((token) => _tokenAliases[token] ?? token)
      .toList(growable: false);

  static _CatalogueSearchIndex _indexFor(Iterable<Product> products) {
    if (products is List<Product>) {
      return _catalogueIndexes[products] ??= _CatalogueSearchIndex(products);
    }
    return _CatalogueSearchIndex(products.toList(growable: false));
  }

  static String _normalize(String value) {
    var result = value.toLowerCase().replaceAll('&', ' and ');
    const accents = <String, String>{
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ï': 'i',
      'ó': 'o',
      'ö': 'o',
      'ú': 'u',
      'ü': 'u',
    };
    accents.forEach((accent, plain) {
      result = result.replaceAll(accent, plain);
    });
    return result
        .replaceAll(RegExp('[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static int _editDistance(String left, String right, {required int limit}) {
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = leftIndex;
      var rowMinimum = current[0];
      for (var rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
        final substitution =
            previous[rightIndex - 1] +
            (left.codeUnitAt(leftIndex - 1) == right.codeUnitAt(rightIndex - 1)
                ? 0
                : 1);
        current[rightIndex] = <int>[
          previous[rightIndex] + 1,
          current[rightIndex - 1] + 1,
          substitution,
        ].reduce((first, second) => first < second ? first : second);
        if (current[rightIndex] < rowMinimum) {
          rowMinimum = current[rightIndex];
        }
      }
      if (rowMinimum > limit) return limit + 1;
      previous = current;
    }
    return previous[right.length];
  }
}

final class _CatalogueSearchIndex {
  _CatalogueSearchIndex(List<Product> products)
    : documents = products.map(_SearchDocument.new).toList(growable: false);

  final List<_SearchDocument> documents;
}

final class _SearchDocument {
  _SearchDocument(this.product)
    : productText = ProductSearch._normalize(
        '${product.name} ${product.subcategory} ${product.description}',
      ),
      name = _SearchField(ProductSearch._normalize(product.name), 120),
      brand = _SearchField(ProductSearch._normalize(product.brand), 100),
      subcategory = _SearchField(
        ProductSearch._normalize(product.subcategory),
        90,
      ),
      description = _SearchField(
        ProductSearch._normalize(product.description),
        45,
      ),
      billingName = _SearchField(
        ProductSearch._normalize(product.billingName),
        35,
      ),
      printName = _SearchField(ProductSearch._normalize(product.printName), 30),
      itemCode = _SearchField(ProductSearch._normalize(product.itemCode), 30),
      barcode = _SearchField(ProductSearch._normalize(product.barcode), 30),
      semantic = _SearchField(ProductSearch._semanticTags(product), 80) {
    fields = [
      name,
      brand,
      subcategory,
      description,
      semantic,
      billingName,
      printName,
      itemCode,
      barcode,
    ];
  }

  final Product product;
  final String productText;
  final _SearchField name;
  final _SearchField brand;
  final _SearchField subcategory;
  final _SearchField description;
  final _SearchField billingName;
  final _SearchField printName;
  final _SearchField itemCode;
  final _SearchField barcode;
  final _SearchField semantic;
  late final List<_SearchField> fields;
}

final class _SearchField {
  _SearchField(this.text, this.weight) : tokens = ProductSearch._tokens(text);

  final String text;
  final int weight;
  final List<String> tokens;
}
