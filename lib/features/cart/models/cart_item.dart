import '../../products/models/product.dart';

class CartItem {
  const CartItem({required this.product, required this.quantity});

  final Product product;
  final int quantity;

  int get totalPaise => product.effectivePricePaise * quantity;
}
