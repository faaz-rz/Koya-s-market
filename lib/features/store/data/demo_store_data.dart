import '../../checkout/models/checkout_models.dart';
import 'generated_product_catalog.dart';

abstract final class DemoStoreData {
  static const minimumDemoStockQuantity = 25;

  static const categories = GeneratedProductCatalog.categories;
  static final products = GeneratedProductCatalog.products
      .map(
        (product) => product.stockQuantity < minimumDemoStockQuantity
            ? product.copyWith(stockQuantity: minimumDemoStockQuantity)
            : product,
      )
      .toList(growable: false);

  static const addresses = [
    CustomerAddress(
      id: 'home-1',
      label: 'Home',
      recipientName: 'Ezlin',
      phone: '+91 98765 43210',
      line1: '12, Lake View Colony, Banjara Hills',
      city: 'Hyderabad',
      pincode: '500034',
      instructions: 'Call when you reach the main gate.',
      isDefault: true,
    ),
  ];

  static const pickupSlots = [FulfilmentSlot(id: 'p1', label: 'Store hours')];

  static const deliverySlots = [
    FulfilmentSlot(id: 'd1', label: '10:00 AM – 1:00 PM'),
    FulfilmentSlot(id: 'd2', label: '2:00 PM – 5:00 PM'),
    FulfilmentSlot(id: 'd3', label: '6:00 PM – 9:00 PM'),
  ];

  static const serviceablePincodes = {
    '500001',
    '500004',
    '500028',
    '500033',
    '500034',
    '500081',
  };
}
