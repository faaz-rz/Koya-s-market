import 'dart:typed_data';

class Product {
  const Product({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.unit,
    required this.pricePaise,
    required this.stockQuantity,
    required this.visualKey,
    this.subcategory = '',
    this.brand = '',
    this.billingName = '',
    this.printName = '',
    this.itemCode = '',
    this.barcode = '',
    this.imageAttribution = '',
    this.imageAsset = '',
    this.imagePath = '',
    this.imageBytes,
    this.discountPricePaise,
    this.imageUrl,
    this.featured = false,
    this.active = true,
  });

  final String id;
  final String categoryId;
  final String name;
  final String description;
  final String unit;
  final int pricePaise;
  final int? discountPricePaise;
  final int stockQuantity;
  final String visualKey;
  final String subcategory;
  final String brand;
  final String billingName;
  final String printName;
  final String itemCode;
  final String barcode;
  final String imageAttribution;
  final String imageAsset;
  final String imagePath;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final bool featured;
  final bool active;

  int get effectivePricePaise => discountPricePaise ?? pricePaise;
  bool get isAvailable => active && stockQuantity > 0;
  int get discountPercent => discountPricePaise == null
      ? 0
      : ((pricePaise - discountPricePaise!) * 100 / pricePaise).round();

  Product copyWith({
    String? categoryId,
    String? name,
    String? description,
    String? unit,
    int? pricePaise,
    int? discountPricePaise,
    int? stockQuantity,
    String? visualKey,
    String? subcategory,
    String? brand,
    String? billingName,
    String? printName,
    String? itemCode,
    String? barcode,
    String? imageAttribution,
    String? imageAsset,
    String? imagePath,
    Uint8List? imageBytes,
    String? imageUrl,
    bool? featured,
    bool? active,
    bool clearDiscount = false,
    bool clearImage = false,
  }) {
    return Product(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      description: description ?? this.description,
      unit: unit ?? this.unit,
      pricePaise: pricePaise ?? this.pricePaise,
      discountPricePaise: clearDiscount
          ? null
          : discountPricePaise ?? this.discountPricePaise,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      visualKey: visualKey ?? this.visualKey,
      subcategory: subcategory ?? this.subcategory,
      brand: brand ?? this.brand,
      billingName: billingName ?? this.billingName,
      printName: printName ?? this.printName,
      itemCode: itemCode ?? this.itemCode,
      barcode: barcode ?? this.barcode,
      imageAttribution: clearImage
          ? ''
          : imageAttribution ?? this.imageAttribution,
      imageAsset: clearImage ? '' : imageAsset ?? this.imageAsset,
      imagePath: clearImage ? '' : imagePath ?? this.imagePath,
      imageBytes: clearImage ? null : imageBytes ?? this.imageBytes,
      imageUrl: clearImage ? null : imageUrl ?? this.imageUrl,
      featured: featured ?? this.featured,
      active: active ?? this.active,
    );
  }
}
