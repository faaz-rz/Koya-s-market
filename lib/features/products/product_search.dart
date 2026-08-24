import 'models/product.dart';

/// Local, relevance-ranked catalogue search for the customer and admin apps.
///
/// Product data stays on-device, while semantic tags make intent searches such
/// as "washing" behave like grocery-app search without requiring a paid search
/// service.
abstract final class ProductSearch {
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
    'with',
  };

  static const _tokenAliases = <String, String>{
    'agarbathi': 'agarbatti',
    'biscuits': 'biscuit',
    'biscot': 'biscuit',
    'biscots': 'biscuit',
    'biscut': 'biscuit',
    'biscuts': 'biscuit',
    'cookies': 'biscuit',
    'detergents': 'detergent',
    'dishes': 'dish',
    'groceries': 'grocery',
    'lotions': 'lotion',
    'powders': 'powder',
    'shampoos': 'shampoo',
    'soaps': 'soap',
    'sweets': 'sweet',
    'utensils': 'utensil',
    'washed': 'wash',
    'washer': 'wash',
    'washes': 'wash',
  };

  static List<Product> search({
    required Iterable<Product> products,
    required String query,
    String? categoryId,
  }) {
    final categoryProducts = products
        .where(
          (product) => categoryId == null || product.categoryId == categoryId,
        )
        .toList(growable: false);
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) return categoryProducts;

    final queryTokens = _tokens(
      normalizedQuery,
    ).where((token) => !_stopWords.contains(token)).toSet();
    if (queryTokens.isEmpty) return categoryProducts;

    final ranked = <({Product product, int score})>[];
    for (final product in categoryProducts) {
      final score = _score(product, normalizedQuery, queryTokens);
      if (score > 0) ranked.add((product: product, score: score));
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

  static int _score(
    Product product,
    String normalizedQuery,
    Set<String> queryTokens,
  ) {
    final name = _SearchField(_normalize(product.name), 120);
    final brand = _SearchField(_normalize(product.brand), 100);
    final subcategory = _SearchField(_normalize(product.subcategory), 90);
    final description = _SearchField(_normalize(product.description), 45);
    final billingName = _SearchField(_normalize(product.billingName), 35);
    final printName = _SearchField(_normalize(product.printName), 30);
    final itemCode = _SearchField(_normalize(product.itemCode), 30);
    final barcode = _SearchField(_normalize(product.barcode), 30);
    final semantic = _SearchField(_semanticTags(product), 80);
    final fields = <_SearchField>[
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

    for (final queryToken in queryTokens) {
      var bestTokenScore = 0;
      for (final field in fields) {
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

final class _SearchField {
  _SearchField(this.text, this.weight) : tokens = ProductSearch._tokens(text);

  final String text;
  final int weight;
  final List<String> tokens;
}
