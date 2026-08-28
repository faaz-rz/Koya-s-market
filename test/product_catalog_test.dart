import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyas_supermarket/features/store/data/demo_store_data.dart';
import 'package:koyas_supermarket/features/store/data/generated_product_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nested downloaded product images are bundled with the app', () async {
    final nestedAsset = GeneratedProductCatalog.products
        .map((product) => product.imageAsset)
        .firstWhere((asset) => asset.startsWith('assets/product_images/web/'));

    final bytes = await rootBundle.load(nestedAsset);
    expect(bytes.lengthInBytes, greaterThan(0));
  });

  test('every storefront category image is bundled with the app', () async {
    const categoryImages = [
      'grocery-staples.png',
      'breakfast-ready-to-cook.png',
      'snacks-sweets.png',
      'beverages.png',
      'dairy-frozen.png',
      'fresh-produce.png',
      'personal-care.png',
      'baby-care.png',
      'home-care.png',
      'health-wellness.png',
      'pooja-festive.png',
      'household-general.png',
    ];

    for (final image in categoryImages) {
      final bytes = await rootBundle.load('assets/category_images/$image');
      expect(bytes.lengthInBytes, greaterThan(0), reason: image);
    }
  });

  test('generated product master catalogue is internally consistent', () {
    final categories = GeneratedProductCatalog.categories;
    final products = GeneratedProductCatalog.products;
    final categoryIds = categories.map((category) => category.id).toSet();
    final productIds = products.map((product) => product.id).toSet();

    expect(categories, hasLength(12));
    expect(products, hasLength(GeneratedProductCatalog.customerProductCount));
    expect(GeneratedProductCatalog.sourceProductCount, 3380);
    expect(
      products.where((product) => product.isAvailable),
      hasLength(GeneratedProductCatalog.availableProductCount),
    );
    expect(products.where((product) => product.featured), hasLength(12));
    expect(products.every((product) => product.billingName.isNotEmpty), isTrue);
    expect(products.every((product) => product.printName.isNotEmpty), isTrue);
    expect(productIds, hasLength(products.length));
    expect(
      products.map((product) => product.name).toSet(),
      hasLength(products.length),
    );
    expect(
      products.every((product) => categoryIds.contains(product.categoryId)),
      isTrue,
    );
    expect(products.every((product) => product.pricePaise > 0), isTrue);
    expect(
      products.every((product) => product.discountPricePaise == null),
      isTrue,
      reason: 'Offers must be created by staff, not imported by default',
    );

    final photographedProducts = products
        .where((product) => product.imageAsset.isNotEmpty)
        .toList(growable: false);
    expect(
      photographedProducts.length / products.length,
      greaterThanOrEqualTo(0.60),
      reason: 'At least 60% of the active catalogue must have product images',
    );
    final openFoodFactsProducts = photographedProducts
        .where(
          (product) => product.imageAttribution.contains('Open Food Facts'),
        )
        .toList(growable: false);
    expect(
      openFoodFactsProducts.map((product) => product.barcode).toSet(),
      containsAll({
        '690225103176',
        '8901063139206',
        '8901063142015',
        '8901725121624',
        '8901808000785',
        '8901808006190',
        '8904103030723',
        '8904109450112',
        '8906022340112',
        '8906022340419',
      }),
    );
    expect(
      photographedProducts.every(
        (product) =>
            File(product.imageAsset).existsSync() &&
            product.imageAttribution.isNotEmpty,
      ),
      isTrue,
    );
    expect(
      products.firstWhere((product) => product.barcode == '8901725121624').unit,
      '5 kg',
    );
    expect(
      products.firstWhere((product) => product.barcode == '690225103176').unit,
      '5 kg',
    );

    final billingNoise = RegExp(
      r'\bRS\s*\.?\d|\bMRP\b|\b(?:SRF|EXL|PDR|BISCOT|BISCUTS|GILLETE|BRITANIA|VASLINE|PANTEEN|KELOGS|GARNR|ALAM|CHICKY|CHOCLATES|COFEE|CORNFLAKS|CUPSICO|DELMONT|EYETX|HARSHEYS|HELMAN|HONRY|INDULEKA|JERSY|KARCK|KISMISS|LABLE|LAIZOL|LICHY|LIJATH|MACRONI|MADJOL|MANGLDEEP|MAYONAISE|MIRICHI|MIROR|MITAYI|MYSRE|NATRJ|NAVRATAN|NAVRATHAN|NESCAFE|NYLN|ODMOS|ORIGANO|PHNOYIL|PITAGIRI|RASBERY|RASBERRY|RESBERRY|SANITERY|SICCORS|SONPAPDI|SURP|SUTHLI|VIBOODI)\b',
      caseSensitive: false,
    );
    expect(
      products.every((product) => !billingNoise.hasMatch(product.name)),
      isTrue,
    );
    expect(
      products.every(
        (product) =>
            product.brand.isEmpty || product.name.contains(product.brand),
      ),
      isTrue,
      reason:
          'Every branded storefront title must visibly show its canonical brand',
    );
    expect(
      products.where((product) => product.brand == 'Surf Excel'),
      isNotEmpty,
    );
    expect(
      products
          .where((product) => product.brand == 'Surf Excel')
          .every((product) => product.name.startsWith('Surf Excel')),
      isTrue,
    );
    expect(
      products.any(
        (product) => product.name == 'Surf Excel Detergent Bar (₹40 Pack)',
      ),
      isTrue,
    );
    final storefrontNames = products.map((product) => product.name).toSet();
    expect(
      storefrontNames,
      containsAll(<String>{
        'Unibic Biscuit',
        'MTR Badam Powder',
        'Lotus Biscoff Biscuits',
        'Patanjali Aloe Vera Shampoo',
        'Amul Paneer Jersey',
        'Cafe Niloufer Platinum Tea Powder 500 g',
        'Eyetex Kajal',
        'Goodknight Mosquito Repellent Agarbatti',
        'M-Seal',
        'Patanjali Dishwash Bar',
        'Shower to Shower Talcum Powder',
        'Gold Drop Edible Oil 1 L',
        'NIVEA Men After Shave Lotion',
        'Vicco Tooth Cream',
      }),
    );
    expect(
      products.every(
        (product) => !<String>{
          'SRF EXL',
          'GILLETE',
          'BRITANIA',
          'VASLINE',
          'PANTEEN',
          'KELOGS',
        }.contains(product.brand),
      ),
      isTrue,
    );
    expect(
      products
          .where((product) => product.brand == 'Comfort')
          .every(
            (product) => product.name.startsWith('Comfort Fabric Conditioner'),
          ),
      isTrue,
    );
    expect(
      products
          .where((product) => product.brand == 'Vim')
          .every((product) => product.name.startsWith('Vim Dishwash')),
      isTrue,
    );
    expect(
      products
          .where((product) => product.brand == 'Listerine')
          .every((product) => product.name.startsWith('Listerine Mouthwash')),
      isTrue,
    );
    expect(
      products
          .where((product) => product.brand == 'Pril')
          .every((product) => product.name.startsWith('Pril Dishwash')),
      isTrue,
    );
  });

  test('client demo keeps every catalogue item available for testing', () {
    expect(
      DemoStoreData.products,
      hasLength(GeneratedProductCatalog.customerProductCount),
    );
    expect(
      DemoStoreData.products.every(
        (product) =>
            product.stockQuantity >= DemoStoreData.minimumDemoStockQuantity,
      ),
      isTrue,
    );
  });
}
